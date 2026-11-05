vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/scheme.vim' as scheme
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('candidate information popup')
const assert = themis#helper('assert')

class Observation
  const popups: list<number>
  const buffers: list<number>
  const lines: list<string>
  const firstline: number
  const height: number
  const buffer: number
  const window: number
  const cursor: list<number>

  def new(this.popups, this.buffers, this.lines, this.firstline, this.height, this.buffer, this.window, this.cursor)
  enddef
endclass

var observations: list<Observation> = []
var ignored_popups: list<number> = []
var origin_buffer: number = 0
const CAPTURE = "\<Cmd>call CaskkTestCandidatePopupCapture()\<CR>"
const WIPE = "\<Cmd>call CaskkTestCandidatePopupWipe()\<CR>"

def g:CaskkTestCandidatePopupCapture()
  const popups = filter(popup_list(), (_, id) => index(ignored_popups, id) < 0)
  const buffers = mapnew(popups, (_, id) => winbufnr(id))
  const lines = len(buffers) == 1 ? getbufline(buffers[0], 1, '$') : []
  const position = len(popups) == 1 ? popup_getpos(popups[0]) : {}
  observations->add(Observation.new(popups, buffers, lines, get(position, 'firstline', 0),
    get(position, 'height', 0), bufnr('%'), win_getid(), [line('.'), col('.')]))
enddef

def g:CaskkTestCandidatePopupWipe()
  execute 'bwipeout! ' .. origin_buffer
enddef

class Fixture
  const previous: number
  const buffer: number
  const window: number
  const directory: string
  const snapshot: user_state.Snapshot
  const existing_buffers: list<number>
  const existing_popups: list<number>

  def new(this.previous, this.buffer, this.window, this.directory, this.snapshot,
      this.existing_buffers, this.existing_popups)
  enddef
endclass

def Setup(candidate_popup: bool = true, extra_mappings: dict<string> = {}, candidate_count: number = 2): Fixture
  const previous = bufnr('%')
  const existing_buffers = mapnew(getbufinfo(), (_, info) => info.bufnr)
  const existing_popups = popup_list()
  ignored_popups = copy(existing_popups)
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  const window = win_getid()
  origin_buffer = number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  const directory = tempname()
  mkdir(directory)
  var dictionary_line = 'か /蚊;昆虫/科;学科'
  for index in range(3, candidate_count)
    dictionary_line ..= '/候補' .. index
  endfor
  writefile([dictionary_line .. '/'], directory .. '/system')
  const snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  observations = []
  Caskk.RegisterInputScheme({name: 'candidate-popup', consonants: {k: 'k'},
    combinations: {a: 'a'}, specials: {d: '漢字', zx: 'い*くらい'}})
  var mappings = {s: 'Convert', n: 'NextCandidate', p: 'PreviousCandidate', c: 'Commit'}
  extend(mappings, extra_mappings)
  Caskk.Config({candidate_popup: candidate_popup, mode_popup: false, dictionaries: [directory .. '/system'],
    mappings: mappings})
  Caskk.Enable('candidate-popup')
  return Fixture.new(previous, number, window, directory, snapshot, existing_buffers, existing_popups)
enddef

def Cleanup(fixture: Fixture)
  try
    win_gotoid(fixture.window)
    Caskk.Disable()
    feedkeys('', 'x')
  finally
    for id in popup_list()
      if index(fixture.existing_popups, id) < 0
        popup_close(id)
      endif
    endfor
    execute 'noautocmd keepalt hide buffer ' .. fixture.previous
    for info in getbufinfo()
      if index(fixture.existing_buffers, info.bufnr) < 0
        execute 'silent! bwipeout! ' .. info.bufnr
      endif
    endfor
    Caskk.Config({})
    user_runtime.Get().Restore(fixture.snapshot)
    delete(fixture.directory, 'rf')
  endtry
enddef

suite.navigation_updates_the_ranked_candidate_list_without_moving_the_input_cursor = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. 'n' .. CAPTURE .. 'p' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['▶ 1/2 蚊 — 昆虫', '  2/2 科 — 学科'])
  assert.equals(observations[1].lines, ['  1/2 蚊 — 昆虫', '▶ 2/2 科 — 学科'])
  assert.equals(observations[2].lines, ['▶ 1/2 蚊 — 昆虫', '  2/2 科 — 学科'])
  for observed in observations
    assert.equals(len(observed.popups), 1)
    assert.equals(observed.buffer, fixture.buffer)
    assert.equals(observed.window, fixture.window)
    assert.equals(observed.cursor, [1, 7])
  endfor
  assert.equals(getline(1), '前蚊後')
}

suite.selected_candidate_stays_inside_a_scrolled_popup_with_many_candidates = (): void => {
  const fixture = Setup(true, {}, 40)
  defer Cleanup(fixture)
  feedkeys('aKas' .. repeat('n', 25) .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(len(observations), 1)
  var selected = -1
  for index in range(len(observations[0].lines))
    if observations[0].lines[index] =~# '^▶'
      selected = index
      break
    endif
  endfor
  assert.equals(selected, 25)
  assert.equals(observations[0].firstline <= selected + 1, true)
  assert.equals(selected + 1 < observations[0].firstline + observations[0].height, true)
}

suite.mapping_removes_the_selected_user_entry_and_refreshes_candidate_selection = (): void => {
  const fixture = Setup(true, {x: 'DeleteUserEntry'})
  defer Cleanup(fixture)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  feedkeys('aKasnnx' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(user_runtime.Get().GetSnapshot().entries, {})
  assert.equals(observations[0].lines,
    ['  1/2 蚊 — 昆虫', '▶ 2/2 科 — 学科'])
  assert.equals(getline(1), '前科後')
}

suite.mappings_toggle_pin_and_demote_for_the_selected_candidate = (): void => {
  const fixture = Setup(true, {v: 'TogglePin', b: 'ToggleDemote'})
  defer Cleanup(fixture)
  feedkeys("aKasv" .. CAPTURE .. "b" .. CAPTURE .. "b" .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['▶ 1/2 ★ 蚊 — 昆虫', '  2/2 科 — 学科'])
  assert.equals(observations[1].lines, ['▶ 1/2 ↓ 蚊 — 昆虫', '  2/2 科 — 学科'])
  assert.equals(observations[2].lines, ['▶ 1/2 蚊 — 昆虫', '  2/2 科 — 学科'])
  const snapshot = user_runtime.Get().GetSnapshot()
  assert.equals(snapshot.pinned, {})
  assert.equals(snapshot.demoted, {})
}

suite.commit_closes_owned_popup_and_buffer_without_closing_an_unrelated_popup = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const foreign = popup_create('別の表示', {line: 1, col: 1})
  ignored_popups->add(foreign)
  feedkeys('aKas' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(len(observations[0].popups), 1)
  assert.equals(empty(popup_getpos(foreign)), false)
  assert.equals(empty(popup_getpos(observations[0].popups[0])), true)
  assert.equals(bufexists(observations[0].buffers[0]), 0)
  normal! u
  assert.equals(getline(1), '前か後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.returning_from_first_candidate_to_reading_closes_the_popup_without_learning = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys('aKas' .. CAPTURE .. 'p' .. CAPTURE .. "\<Esc>", 'xt')
  assert.equals(len(observations[0].popups), 1)
  assert.equals(observations[1].popups, [])
  assert.equals(getline(1), '前か後')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.exhaustion_closes_candidate_popup_before_opening_registration = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. 'nn' .. CAPTURE .. "\<Esc>\<Esc>", 'xt')
  assert.equals(len(observations[0].popups), 1)
  assert.equals(observations[1].popups, [])
  assert.equals(observations[1].buffer != fixture.buffer, true)
  assert.equals(bufexists(observations[0].buffers[0]), 0)
  assert.equals(getline(1), '前か後')
}

suite.cancelling_registration_discards_the_inner_candidate_popup_without_learning = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys('aZX' .. "\<BS>Kas" .. CAPTURE .. "\<Esc>ka\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['▶ 1/2 蚊 — 昆虫', '  2/2 科 — 学科'])
  assert.equals(empty(popup_getpos(observations[0].popups[0])), true)
  assert.equals(bufexists(observations[0].buffers[0]), 0)
  assert.equals(getline(1), '前いくらいか後')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.wiping_the_input_buffer_closes_the_popup_after_normal_session_commit = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. WIPE .. "\<Esc>", 'xt')
  assert.equals(len(observations[0].popups), 1)
  assert.equals(empty(popup_getpos(observations[0].popups[0])), true)
  assert.equals(bufexists(observations[0].buffers[0]), 0)
  assert.equals(bufexists(fixture.buffer), 0)
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['か', ''])], ['蚊'])
  assert.equals(user_runtime.Get().GetSnapshot().entries, {})
}

suite.disabling_popup_and_rejecting_invalid_setting_does_not_disable_conversion = (): void => {
  const fixture = Setup(false)
  defer Cleanup(fixture)
  var caught = ''
  try
    Caskk.Config({candidate_popup: 1})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: invalid configuration: candidate_popup must be a bool')
  feedkeys('aKas' .. CAPTURE .. 'n' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].popups, [])
  assert.equals(observations[1].popups, [])
  assert.equals(getline(1), '前科後')
}
