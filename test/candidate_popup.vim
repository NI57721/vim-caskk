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
  const position: dict<number>
  const cursor: list<number>

  def new(this.popups, this.buffers, this.lines, this.firstline, this.height, this.buffer, this.window, this.cursor, this.position)
  enddef
endclass

var observations: list<Observation> = []
var selected_rows: list<number> = []
var selection_groups: list<string> = []
var ignored_popups: list<number> = []
var origin_buffer: number = 0
const CAPTURE = "\<Cmd>call CaskkTestCandidatePopupCapture()\<CR>"
const WIPE = "\<Cmd>call CaskkTestCandidatePopupWipe()\<CR>"

def g:CaskkTestCandidatePopupCapture()
  const popups = filter(popup_list(), (_, id) => index(ignored_popups, id) < 0)
  const buffers = mapnew(popups, (_, id) => winbufnr(id))
  const lines = len(buffers) == 1 ? getbufline(buffers[0], 1, '$') : []
  const position = len(popups) == 1 ? popup_getpos(popups[0]) : {}
  var selected_row = 0
  if len(buffers) == 1
    for row in range(1, len(lines))
      if !empty(filter(prop_list(row, {bufnr: buffers[0]}), (_, property) => property.type ==# 'caskk_candidate_selected'))
        selected_row = row
      endif
    endfor
  endif
  selected_rows->add(selected_row)
  selection_groups->add(len(buffers) == 1
    ? get(prop_type_get('caskk_candidate_selected', {bufnr: buffers[0]}), 'highlight', '') : '')
  observations->add(Observation.new(popups, buffers, lines, get(position, 'firstline', 0),
    get(position, 'height', 0), bufnr('%'), win_getid(), [line('.'), col('.')], position))
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
  selected_rows = []
  selection_groups = []
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
  assert.equals(observations[0].lines, ['1/2 蚊 — 昆虫', '2/2 科 — 学科'])
  assert.equals(observations[1].lines, ['1/2 蚊 — 昆虫', '2/2 科 — 学科'])
  assert.equals(observations[2].lines, ['1/2 蚊 — 昆虫', '2/2 科 — 学科'])
  for observed in observations
    assert.equals(len(observed.popups), 1)
    assert.equals(observed.buffer, fixture.buffer)
    assert.equals(observed.window, fixture.window)
    assert.equals(observed.cursor, [1, 7])
  endfor
  assert.equals(getline(1), '前蚊後')
  assert.equals(selected_rows, [1, 2, 1])
  assert.equals(selection_groups, ['PmenuSel', 'PmenuSel', 'PmenuSel'])
}

suite.selected_candidate_stays_inside_a_scrolled_popup_with_many_candidates = (): void => {
  const fixture = Setup(true, {}, 40)
  defer Cleanup(fixture)
  feedkeys('aKas' .. repeat('n', 25) .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(len(observations), 1)
  const selected = selected_rows[0] - 1
  assert.equals(selected, 25)
  assert.equals(observations[0].firstline <= selected + 1, true)
  assert.equals(selected + 1 < observations[0].firstline + observations[0].height, true)
}

suite.mapping_removes_the_selected_user_entry_and_refreshes_candidate_selection = (): void => {
  const fixture = Setup(true, {x: 'DeleteUserEntry'})
  defer Cleanup(fixture)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  feedkeys('aKasnnx' .. CAPTURE .. 'y' .. CAPTURE .. "c\<Esc>", 'xt')
  const identity = json_encode(['か', ''])
  assert.equals(observations[0].lines[-1], 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消')
  assert.equals(has_key(user_runtime.Get().GetSnapshot().entries, identity), false)
  assert.equals(user_runtime.Get().GetSnapshot().entries, {})
  assert.equals(observations[1].lines,
    ['1/2 蚊 — 昆虫', '2/2 科 — 学科'])
  assert.equals(getline(1), '前科後')
}

suite.cancelling_user_entry_deletion_keeps_the_entry_and_selected_candidate = (): void => {
  const fixture = Setup(true, {x: 'DeleteUserEntry'})
  defer Cleanup(fixture)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  const identity = json_encode(['か', ''])
  feedkeys('aKasnnx' .. CAPTURE .. 'n' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(has_key(user_runtime.Get().GetSnapshot().entries, identity), true)
  assert.equals(user_runtime.Get().GetSnapshot().entries[identity][0].text, '登録のみ')
  assert.equals(observations[0].lines[-1], 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消')
  assert.equals(observations[1].lines[-1], '3/3 登録のみ')
  assert.equals(getline(1), '前登録のみ後')
}

suite.esc_cancels_user_entry_deletion_without_leaving_the_candidate = (): void => {
  const fixture = Setup(true, {x: 'DeleteUserEntry'})
  defer Cleanup(fixture)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  const identity = json_encode(['か', ''])
  feedkeys('aKasnnx' .. CAPTURE .. "\<Esc>" .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines[-1], 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消')
  assert.equals(observations[1].lines[-1], '3/3 登録のみ')
  assert.equals(has_key(user_runtime.Get().GetSnapshot().entries, identity), true)
  assert.equals(getline(1), '前登録のみ後')
}

suite.mappings_toggle_pin_and_demote_for_the_selected_candidate = (): void => {
  const fixture = Setup(true, {v: 'TogglePin', b: 'ToggleDemote'})
  defer Cleanup(fixture)
  feedkeys("aKasv" .. CAPTURE .. "b" .. CAPTURE .. "b" .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['1/2 ★ 蚊 — 昆虫', '2/2 科 — 学科'])
  assert.equals(observations[1].lines, ['1/2 ↓ 蚊 — 昆虫', '2/2 科 — 学科'])
  assert.equals(observations[2].lines, ['1/2 蚊 — 昆虫', '2/2 科 — 学科'])
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
  assert.equals(observations[0].lines, ['1/2 蚊 — 昆虫', '2/2 科 — 学科'])
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

suite.candidate_popup_keeps_its_position_and_height_near_the_end = (): void => {
  const fixture = Setup(true, {}, 40)
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. repeat('n', 36) .. CAPTURE .. 'nn' .. CAPTURE .. "c\<Esc>", 'xt')
  const initial = observations[0].position
  for observed in observations[1 : ]
    assert.equals([observed.position.line, observed.position.col, observed.height],
      [initial.line, initial.col, observations[0].height])
  endfor
}

suite.deletion_confirmation_is_fully_visible_in_a_small_terminal = (): void => {
  const script = tempname() .. '.vim'
  const report = tempname()
  defer delete(script)
  defer delete(report)
  writefile([
    'vim9script',
    'set rtp^=' .. escape(getcwd(), ' ,'),
    'const inline = readfile(' .. string(report) .. ')[0] ==# "inline"',
    "import autoload 'caskk.vim' as C",
    "import autoload 'caskk/user_state/runtime.vim' as runtime",
    "import autoload 'caskk/dictionary/lookup.vim' as lookup",
    "import 'caskk/dictionary.vim' as dictionary",
    "C.RegisterInputScheme({name: 'small-confirmation', consonants: {k: 'k'}, combinations: {a: 'a', i: 'i'}})",
    "C.Config({mode_popup: false, registration_auto: false, registration_inline: inline, registration_prefill: false, mappings: {s: 'Convert', x: 'DeleteUserEntry', q: 'OpenRegistration'}})",
    "runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('蚊', []))",
    "C.Enable('small-confirmation')",
    'def Capture(timer: number)',
    "  writefile([string(runtime.Get().HasEntryForLookup(lookup.CreateQuery('か', ''), '蚊'))], " .. string(report) .. ')',
    'enddef',
    'timer_start(10, Capture, {repeat: -1})',
    'writefile(["ready"], ' .. string(report) .. ')',
  ], script)
  for dimensions in [[8, 24, false], [6, 36, false], [8, 24, true], [6, 36, true]]
    writefile([dimensions[2] ? 'inline' : 'normal'], report)
    const terminal = term_start([v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-N', '-S', script],
      {hidden: true, term_rows: dimensions[0], term_cols: dimensions[1]})
    try
      for _ in range(100)
        term_wait(terminal, 10)
        if readfile(report) == ['ready'] || readfile(report) == ['true']
          break
        endif
      endfor
      term_sendkeys(terminal, dimensions[2] ? 'iKisqKasx' : 'iKasx')
      term_wait(terminal, 100)
      const screen = join(mapnew(range(1, dimensions[0]), (_, row) => term_getline(terminal, row)), '')
      # Ignore background cells and Vim's filler before a wrapped wide character.
      const compact = substitute(screen, '[[:space:]~>]', '', 'g')
      assert.equals(stridx(compact, 'ユーザー辞書から削除しますか？y:削除n/Esc:取消') >= 0, true, screen)
      term_sendkeys(terminal, 'n')
      term_wait(terminal, 100)
      assert.equals(readfile(report), ['true'])
      const restored = join(mapnew(range(1, dimensions[0]), (_, row) => term_getline(terminal, row)), '')
      assert.equals(stridx(restored, dimensions[2] ? '辞書登録' : '1/1 蚊') >= 0, true, restored)
      term_sendkeys(terminal, 'xy')
      term_wait(terminal, 100)
      assert.equals(readfile(report), ['false'])
    finally
      job_stop(term_getjob(terminal), 'kill')
      execute 'silent! bwipeout! ' .. terminal
    endtry
  endfor
}

suite.explicit_backspace_delete_mapping_keeps_its_confirmation_behavior = (): void => {
  const fixture = Setup(true, {"\<BS>": 'DeleteUserEntry'})
  defer Cleanup(fixture)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  feedkeys('aKasnn' .. "\<BS>" .. CAPTURE .. 'y' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines[-1], 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消')
  assert.equals(user_runtime.Get().HasEntryForLookup(lookup.CreateQuery('か', ''), '登録のみ'), false)
  assert.equals(observations[1].lines, ['1/2 蚊 — 昆虫', '2/2 科 — 学科'])
}

suite.unavailable_backspace_actions_cancel_conversion_without_learning = (): void => {
  for action in ['DeleteUserEntry', 'KatakanaMode', 'OpenRegistration', 'ShowCompletion', 'CancelCompletion']
    const fixture = Setup(true, {"\<BS>": action})
    try
      feedkeys('aKas' .. "\<BS>" .. CAPTURE .. "\<Esc>", 'xt')
      assert.equals(getline(1), '前後', action)
      assert.equals(observations[0].popups, [], action)
      assert.equals(user_runtime.Get().GetSnapshot().mru, {}, action)
    finally
      Cleanup(fixture)
    endtry
  endfor
}
