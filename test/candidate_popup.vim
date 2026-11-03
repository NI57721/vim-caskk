vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('candidate information popup')
const assert = themis#helper('assert')

class Observation
  const popups: list<number>
  const buffers: list<number>
  const lines: list<string>
  const buffer: number
  const window: number
  const cursor: list<number>

  def new(this.popups, this.buffers, this.lines, this.buffer, this.window, this.cursor)
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
  observations->add(Observation.new(popups, buffers, lines, bufnr('%'), win_getid(), [line('.'), col('.')]))
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

def Setup(candidate_popup: bool = true): Fixture
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
  writefile(['か /蚊;昆虫/科;学科/'], directory .. '/system')
  const snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  observations = []
  Caskk.RegisterInputScheme('candidate-popup', {k: 'k'}, {a: 'a'},
    {d: '漢字', zx: 'い*くらい'})
  Caskk.Config({candidate_popup: candidate_popup, dictionaries: [directory .. '/system'],
    mappings: {s: 'Convert', n: 'NextCandidate', p: 'PreviousCandidate', c: 'Commit'}})
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

suite.navigation_shows_position_and_annotations_without_moving_the_input_cursor = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. 'n' .. CAPTURE .. 'p' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['1/2 蚊', '昆虫'])
  assert.equals(observations[1].lines, ['2/2 科', '学科'])
  assert.equals(observations[2].lines, ['1/2 蚊', '昆虫'])
  for observed in observations
    assert.equals(len(observed.popups), 1)
    assert.equals(observed.buffer, fixture.buffer)
    assert.equals(observed.window, fixture.window)
    assert.equals(observed.cursor, [1, 7])
  endfor
  assert.equals(getline(1), '前蚊後')
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
  assert.equals(observations[0].lines, ['1/2 蚊', '昆虫'])
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
