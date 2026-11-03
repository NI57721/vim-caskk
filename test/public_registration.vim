vim9script

import autoload 'caskk.vim' as Caskk
import 'caskk/registration.vim' as registration
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/user_state/store.vim' as store
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('public dictionary registration')
const assert = themis#helper('assert')
var requests: list<registration.Request> = []
var errors: list<string> = []

class Fixture
  const previous: number
  const buffer: number
  const directory: string
  const snapshot: user_state.Snapshot

  def new(this.previous, this.buffer, this.directory, this.snapshot)
  enddef
endclass

def Handle(action: string)
  try
    if action ==# 'request'
      requests->add(Caskk.GetRegistrationRequest())
    elseif action ==# 'complete'
      Caskk.CompleteRegistration('課', ['登録注釈'])
    elseif action ==# 'okuri'
      Caskk.CompleteRegistration('行', ['移動'])
    elseif action ==# 'empty'
      Caskk.CompleteRegistration('')
    elseif action ==# 'cancel'
      Caskk.CancelRegistration()
    elseif action ==# 'moved'
      const position = getcurpos()
      cursor(1, 1)
      try
        Caskk.CompleteRegistration('不正')
      finally
        setpos('.', position)
      endtry
    endif
  catch
    errors->add(v:exception)
  endtry
enddef

def Setup(lines: list<string> = []): Fixture
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  const directory = tempname()
  mkdir(directory)
  writefile(lines, directory .. '/system')
  const snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  requests = []
  errors = []
  Caskk.RegisterInputScheme('public-registration', {k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい'),
  ])
  Caskk.Config({registration_auto: false, state_path: directory .. '/state.jsonl', dictionaries: [directory .. '/system'],
    mappings: {s: 'Convert', n: 'NextCandidate'}})
  Caskk.Enable('public-registration')
  inoremap <buffer> <F3> <ScriptCmd>Handle('complete')<CR>
  inoremap <buffer> <F4> <ScriptCmd>Handle('okuri')<CR>
  inoremap <buffer> <F5> <ScriptCmd>Handle('cancel')<CR>
  inoremap <buffer> <F6> <ScriptCmd>Handle('request')<CR>
  inoremap <buffer> <F7> <ScriptCmd>Handle('empty')<CR>
  inoremap <buffer> <F8> <ScriptCmd>Handle('moved')<CR>
  return Fixture.new(previous, number, directory, snapshot)
enddef

def Cleanup(fixture: Fixture)
  try
    Caskk.Disable()
    Caskk.Config({})
  finally
    user_runtime.Get().Restore(fixture.snapshot)
    execute 'noautocmd keepalt hide buffer ' .. fixture.previous
    execute 'silent! bwipeout! ' .. fixture.buffer
    delete(fixture.directory, 'rf')
  endtry
enddef

suite.registration_replaces_preedit_and_persists_body_annotations_and_learning = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys("aKas\<F6>\<F3>\<F6>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(requests[0].reading, 'か')
  assert.equals(requests[0].okuri, '')
  assert.equals(requests[0].exact_okuri, '')
  assert.equals(requests[0].lookup_key, 'か')
  assert.equals(requests[1] is null_object, true)
  assert.equals(getline(1), '前課か後')
  Caskk.SaveState()
  const stored = store.Load(fixture.directory .. '/state.jsonl')
  const identity = json_encode(['か', ''])
  assert.equals(stored.entries[identity][0].text, '課')
  assert.equals(stored.entries[identity][0].annotations, ['登録注釈'])
  assert.equals(stored.mru[identity], ['課'])
  for expected in ['前課後', '前か後', '前後']
    normal! u
    assert.equals(getline(1), expected)
  endfor
}

suite.okuri_request_and_completion_keep_exact_okuri_separate_from_full_suffix = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys("aZX\<F6>\<F4>\<F6>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(requests[0].reading, 'い')
  assert.equals(requests[0].exact_okuri, 'く')
  assert.equals(requests[0].lookup_key, 'いk')
  assert.equals(requests[0].okuri, 'くらい')
  assert.equals(requests[1] is null_object, true)
  assert.equals(getline(1), '前行くらい後')
  Caskk.SaveState()
  const stored = store.Load(fixture.directory .. '/state.jsonl')
  assert.equals(stored.entries[json_encode(['い', 'く'])][0].text, '行')
}

suite.cancellation_keeps_reading_editable_without_changing_shared_state = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys("aKas\<F6>\<F5>\<F6>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(requests[0].reading, 'か')
  assert.equals(requests[1] is null_object, true)
  assert.equals(getline(1), '前かか後')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.exhaustion_can_register_a_new_candidate_used_by_the_next_conversion = (): void => {
  const fixture = Setup(['いk /行/'])
  defer Cleanup(fixture)
  feedkeys("aZXn\<F6>\<F3>ZX\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(requests[0].reading, 'い')
  assert.equals(requests[0].okuri, 'くらい')
  assert.equals(getline(1), '前課くらい課くらい後')
  assert.equals(readfile(fixture.directory .. '/system'), ['いk /行/'])
}

suite.empty_candidate_and_moved_cursor_leave_the_request_available_for_retry = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys("aKas\<F7>\<F8>\<F6>\<F3>\<Esc>", 'xt')
  assert.equals(errors, [
    'caskk: registered candidate text must not be empty',
    'caskk: cursor moved outside the tracked input position',
  ])
  assert.equals(requests[0].reading, 'か')
  assert.equals(getline(1), '前課後')
  const candidates = user_runtime.Get().GetSnapshot().entries[json_encode(['か', ''])]
  assert.equals(len(candidates), 1)
  assert.equals(candidates[0].text, '課')
}

suite.direct_preedit_and_candidate_selection_do_not_expose_a_registration_request = (): void => {
  const fixture = Setup(['か /蚊/'])
  defer Cleanup(fixture)
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
  feedkeys("a\<F6>Ka\<F6>s\<F6>\<F3>\<Esc>", 'xt')
  assert.equals(errors, ['caskk: no current dictionary registration request'])
  assert.equals(len(requests), 3)
  for request in requests
    assert.equals(request is null_object, true)
  endfor
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
  assert.equals(getline(1), '前蚊後')
  assert.equals(user_runtime.Get().GetSnapshot().entries, {})
}

suite.disabled_buffer_rejects_completion_and_cancellation_without_changing_state = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  Caskk.Disable()
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
  Handle('complete')
  Handle('cancel')
  assert.equals(errors, [
    'caskk: no current dictionary registration request',
    'caskk: no current dictionary registration request',
  ])
  assert.equals(getline(1), '前後')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}
