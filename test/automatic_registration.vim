vim9script

import autoload 'caskk.vim' as Caskk
import 'caskk/registration.vim' as registration
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/user_state/codec.vim' as codec
import autoload 'caskk/user_state/store.vim' as store

final suite = themis#suite('automatic dictionary registration')
const assert = themis#helper('assert')

class Observation
  const buffer: number
  const window: number
  const text: string
  const highlights: number
  const request: registration.Request

  def new(this.buffer, this.window, this.text, this.highlights, this.request)
  enddef
endclass

var observations: list<Observation> = []
var origin_buffer: number = 0
var origin_window: number = 0
const CAPTURE = "\<Cmd>call CaskkTestAutoRegistrationCapture()\<CR>"

def g:CaskkTestAutoRegistrationCapture()
  observations->add(Observation.new(bufnr('%'), win_getid(), getline(1),
    len(prop_list(1, {types: ['caskk_preedit']})), Caskk.GetRegistrationRequest()))
enddef

def g:CaskkTestAutoRegistrationDestroy(target: string)
  if len(observations) != 2
    throw 'test: two registration windows must be open'
  endif
  if target ==# 'inner-window'
    close!
  elseif target ==# 'outer-window'
    win_execute(observations[0].window, 'close!')
  elseif target ==# 'outer-buffer'
    execute 'bwipeout! ' .. observations[0].buffer
  elseif target ==# 'origin-window'
    win_execute(origin_window, 'close!')
  elseif target ==# 'origin-buffer'
    execute 'bwipeout! ' .. origin_buffer
  else
    throw 'test: unknown destruction target: ' .. target
  endif
enddef

def DestroyCommand(target: string): string
  return "\<Cmd>call CaskkTestAutoRegistrationDestroy(" .. string(target) .. ")\<CR>"
enddef

class Fixture
  const previous: number
  const buffer: number
  const window: number
  const directory: string
  const snapshot: user_state.Snapshot
  const existing_buffers: list<number>

  def new(this.previous, this.buffer, this.window, this.directory, this.snapshot, this.existing_buffers)
  enddef
endclass

def Setup(lines: list<string> = [], registration_prefill: bool = true): Fixture
  const previous = bufnr('%')
  const existing_buffers = mapnew(getbufinfo(), (_, info) => info.bufnr)
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  const window = win_getid()
  origin_buffer = number
  origin_window = window
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  const directory = tempname()
  mkdir(directory)
  writefile(lines, directory .. '/system')
  const snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  observations = []
  Caskk.RegisterInputScheme('automatic-registration', {k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['d'], '漢字'),
    scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい'),
  ])
  Caskk.Config({registration_prefill: registration_prefill,
    state_path: directory .. '/state.jsonl', dictionaries: [directory .. '/system'],
    mappings: {s: 'StartConversion', n: 'NextCandidate', '<F6>': 'OpenRegistration'}})
  Caskk.Enable('automatic-registration')
  return Fixture.new(previous, number, window, directory, snapshot, existing_buffers)
enddef

def Cleanup(fixture: Fixture)
  try
    win_gotoid(fixture.window)
    Caskk.Disable()
    feedkeys('', 'x')
  finally
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

suite.missing_candidates_open_registration_without_an_extra_action = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const windows = winnr('$')
  feedkeys('aKas' .. CAPTURE .. "\<BS>d\<CR>ka\<Esc>", 'xt')
  assert.equals(len(observations), 1)
  assert.equals(observations[0].buffer != fixture.buffer, true)
  assert.equals(observations[0].text, 'か')
  assert.equals(observations[0].highlights, 1)
  assert.equals(getline(1), '前漢字か後')
  assert.equals(winnr('$'), windows)
  assert.equals(bufexists(observations[0].buffer), 0)
  Caskk.SaveState()
  assert.equals(store.Load(fixture.directory .. '/state.jsonl').entries[json_encode(['か', ''])][0].text, '漢字')
  for expected in ['前漢字後', '前か後', '前後']
    normal! u
    assert.equals(getline(1), expected)
  endfor
}

suite.missing_okuri_candidate_opens_registration_as_soon_as_okuri_is_complete = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys('aZX' .. CAPTURE .. "\<BS>d\<CR>\<Esc>", 'xt')
  assert.equals(observations[0].buffer != fixture.buffer, true)
  assert.equals(observations[0].text, 'い')
  assert.equals(getline(1), '前漢字くらい後')
  const stored = user_runtime.Get().GetSnapshot().entries[json_encode(['い', 'く'])]
  assert.equals(stored[0].text, '漢字')
}

suite.exhausting_candidates_opens_registration_without_learning_the_last_selection = (): void => {
  const fixture = Setup(['か /蚊/'])
  defer Cleanup(fixture)
  feedkeys('aKasn' .. CAPTURE .. "\<BS>d\<CR>\<Esc>", 'xt')
  assert.equals(observations[0].buffer != fixture.buffer, true)
  assert.equals(observations[0].text, 'か')
  assert.equals(getline(1), '前漢字後')
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['か', ''])], ['漢字'])
  assert.equals(readfile(fixture.directory .. '/system'), ['か /蚊/'])
}

suite.cancelling_automatic_registration_does_not_reopen_it_or_learn = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  const windows = winnr('$')
  feedkeys('aKas' .. CAPTURE .. "\<Esc>" .. CAPTURE .. "ka\<Esc>", 'xt')
  assert.equals(observations[0].buffer != fixture.buffer, true)
  assert.equals(observations[1].buffer, fixture.buffer)
  assert.equals(observations[1].text, '前か後')
  assert.equals(getline(1), '前かか後')
  assert.equals(winnr('$'), windows)
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.disabling_automatic_registration_keeps_requests_and_manual_opening_available = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  Caskk.Disable()
  Caskk.Config({registration_auto: false,
    mappings: {s: 'StartConversion', '<F6>': 'OpenRegistration'}})
  Caskk.Enable('automatic-registration')
  feedkeys('aKas' .. CAPTURE .. "\<F6>" .. CAPTURE .. "\<BS>d\<CR>\<Esc>", 'xt')
  assert.equals(observations[0].buffer, fixture.buffer)
  assert.equals(observations[0].request.reading, 'か')
  assert.equals(observations[1].buffer != fixture.buffer, true)
  assert.equals(getline(1), '前漢字後')
}

suite.invalid_automatic_setting_keeps_the_previous_manual_mode = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  Caskk.Disable()
  Caskk.Config({registration_auto: false, mappings: {s: 'StartConversion'}})
  var caught = ''
  try
    Caskk.Config({registration_auto: 1})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: invalid configuration: registration_auto must be a bool')
  Caskk.Enable('automatic-registration')
  feedkeys('aKas' .. CAPTURE .. "\<Esc>", 'xt')
  assert.equals(observations[0].buffer, fixture.buffer)
  assert.equals(observations[0].request.reading, 'か')
}

suite.registration_input_can_open_a_nested_request_and_return_through_both_windows = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const windows = winnr('$')
  feedkeys('aKas' .. CAPTURE .. 's' .. CAPTURE .. "\<BS>d\<CR>\<CR>ka\<Esc>", 'xt')
  assert.equals(len(observations), 2)
  assert.equals(observations[0].buffer != observations[1].buffer, true)
  assert.equals(observations[0].text, 'か')
  assert.equals(observations[1].text, 'か')
  assert.equals(getline(1), '前漢字か後')
  assert.equals(winnr('$'), windows)
  for observed in observations
    assert.equals(bufexists(observed.buffer), 0)
  endfor
  const candidates = user_runtime.Get().GetSnapshot().entries[json_encode(['か', ''])]
  assert.equals(len(candidates), 1)
  assert.equals(candidates[0].text, '漢字')
}

suite.automatic_registration_honors_disabled_prefill = (): void => {
  const fixture = Setup([], false)
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. "d\<CR>\<Esc>", 'xt')
  assert.equals(observations[0].buffer != fixture.buffer, true)
  assert.equals(observations[0].text, '')
  assert.equals(observations[0].highlights, 0)
  assert.equals(getline(1), '前漢字後')
}

suite.cancelling_nested_registration_keeps_the_outer_input_open = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const windows = winnr('$')
  feedkeys('aKas' .. CAPTURE .. 's' .. CAPTURE .. "\<Esc>" .. CAPTURE
    .. "\<BS>d\<CR>\<Esc>", 'xt')
  assert.equals(len(observations), 3)
  assert.equals(observations[0].buffer != observations[1].buffer, true)
  assert.equals(observations[2].buffer, observations[0].buffer)
  assert.equals(observations[2].text, 'か')
  assert.equals(getline(1), '前漢字後')
  assert.equals(winnr('$'), windows)
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['か', ''])], ['漢字'])
}

suite.closing_inner_window_returns_to_outer_registration_and_allows_completion = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const windows = winnr('$')
  feedkeys('aKas' .. CAPTURE .. 's' .. CAPTURE .. "\<C-c>" .. DestroyCommand('inner-window')
    .. CAPTURE .. "\<BS>d\<CR>\<Esc>", 'xt')
  assert.equals(observations[2].buffer, observations[0].buffer)
  assert.equals(observations[2].text, 'か')
  assert.equals(getline(1), '前漢字後')
  assert.equals(winnr('$'), windows)
  assert.equals(bufexists(observations[0].buffer), 0)
  assert.equals(bufexists(observations[1].buffer), 0)
  const entries = user_runtime.Get().GetSnapshot().entries[json_encode(['か', ''])]
  assert.equals(len(entries), 1)
  assert.equals(entries[0].text, '漢字')
}

suite.closing_outer_window_cancels_both_levels_without_registering = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  const windows = winnr('$')
  feedkeys('aKas' .. CAPTURE .. 's' .. CAPTURE .. "\<C-c>" .. DestroyCommand('outer-window')
    .. CAPTURE .. "ka\<Esc>", 'xt')
  assert.equals(observations[2].buffer, fixture.buffer)
  assert.equals(getline(1), '前かか後')
  assert.equals(winnr('$'), windows)
  assert.equals(bufexists(observations[0].buffer), 0)
  assert.equals(bufexists(observations[1].buffer), 0)
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.wiping_outer_input_cancels_both_levels_and_removes_inner_buffer = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  const windows = winnr('$')
  feedkeys('aKas' .. CAPTURE .. 's' .. CAPTURE .. "\<C-c>" .. DestroyCommand('outer-buffer')
    .. CAPTURE .. "ka\<Esc>", 'xt')
  assert.equals(observations[2].buffer, fixture.buffer)
  assert.equals(getline(1), '前かか後')
  assert.equals(winnr('$'), windows)
  assert.equals(bufexists(observations[0].buffer), 0)
  assert.equals(bufexists(observations[1].buffer), 0)
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.wiping_origin_during_nested_registration_does_not_leave_orphaned_inputs = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  const windows = winnr('$')
  feedkeys('aKas' .. CAPTURE .. 's' .. CAPTURE .. "\<C-c>" .. DestroyCommand('origin-buffer'), 'xt')
  assert.equals(bufexists(fixture.buffer), 0)
  assert.equals(bufexists(observations[0].buffer), 0)
  assert.equals(bufexists(observations[1].buffer), 0)
  assert.equals(winnr('$'), windows)
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.closing_origin_during_nested_registration_preserves_plain_reading = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  const windows = winnr('$')
  feedkeys('aKas' .. CAPTURE .. 's' .. CAPTURE .. "\<C-c>" .. DestroyCommand('origin-window'), 'xt')
  assert.equals(getbufline(fixture.buffer, 1), ['前か後'])
  assert.equals(prop_list(1, {bufnr: fixture.buffer}), [])
  assert.equals(bufexists(observations[0].buffer), 0)
  assert.equals(bufexists(observations[1].buffer), 0)
  assert.equals(winnr('$'), windows)
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}
