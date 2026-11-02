vim9script

import autoload 'caskk/binding.vim' as binding
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec
import 'caskk/dictionary.vim' as dictionary

final suite = themis#suite('registration suspension across windows')
const assert = themis#helper('assert')
var source: binding.Binding
var child: binding.Binding
var compiled: scheme.CompiledScheme
var preferences: user_state.State
var source_window: number
var source_buffer: number
var source_position: list<number> = []
var child_window: number = 0
var child_buffer: number = 0
var errors: list<string> = []
var source_texts: list<string> = []
var suspended: list<bool> = []
var highlight_counts: list<number> = []
var child_text_override: string = ''
var return_insertions: number = 0

augroup caskk_test_registration_return
augroup END

def MutateOnReturn()
  setline(1, '外部変更')
enddef

def CountReturn()
  return_insertions += 1
enddef

def RecordSource()
  source_texts->add(getbufline(source_buffer, 1)[0])
  suspended->add(source.GetEditor().IsRegistrationSuspended())
  highlight_counts->add(len(prop_list(1, {bufnr: source_buffer, types: ['caskk_preedit']})))
enddef

def OpenChild()
  source.SuspendRegistration()
  source_position = getcurpos()
  belowright split
  child_window = win_getid()
  child_buffer = bufadd('')
  bufload(child_buffer)
  execute 'buffer ' .. child_buffer
  setlocal buftype=nofile bufhidden=wipe noswapfile
  child = binding.Binding.new(compiled)
  child.Enable()
  inoremap <buffer> <F4> <ScriptCmd>Handle('complete')<CR>
  inoremap <buffer> <F5> <ScriptCmd>Handle('cancel')<CR>
  inoremap <buffer> <F6> <ScriptCmd>Handle('wrong-window')<CR>
  inoremap <buffer> <F7> <ScriptCmd>Handle('guard')<CR>
  inoremap <buffer> <F8> <ScriptCmd>Handle('external')<CR>
  inoremap <buffer> <F9> <ScriptCmd>Handle('disable')<CR>
  inoremap <buffer> <F10> <ScriptCmd>Handle('normal-complete')<CR>
  nnoremap <buffer> <F4> <ScriptCmd>Handle('normal-complete')<CR>
  nnoremap <buffer> <F5> <ScriptCmd>Handle('normal-cancel')<CR>
  nnoremap <buffer> <F6> <ScriptCmd>Handle('normal-wrong-window')<CR>
  nnoremap <buffer> <F7> <ScriptCmd>Handle('normal-duplicate')<CR>
  nnoremap <buffer> <F8> <ScriptCmd>Handle('normal-external')<CR>
  nnoremap <buffer> <F9> <ScriptCmd>Handle('normal-disable')<CR>
  nnoremap <buffer> <F10> <ScriptCmd>Handle('normal-external-on-enter')<CR>
  RecordSource()
enddef

def ReturnToSource(): string
  child.Disable()
  const text = join(getbufline(child_buffer, 1, '$'), "\n")
  win_gotoid(source_window)
  setpos('.', source_position)
  win_execute(child_window, 'close!')
  return text
enddef

def AttemptSuspendedInput(action: string)
  try
    if action ==# 'native'
      source.Dispatch('<Left>')
    elseif action ==# 'input'
      source.Dispatch('a')
    elseif action ==# 'enter'
      source.Enter()
    else
      source.CompleteRegistration('不正')
    endif
  catch
    errors->add(v:exception)
  endtry
enddef

def Handle(action: string)
  try
    if action ==# 'open'
      OpenChild()
    elseif action ==# 'wrong-window'
      source.ResumeRegistration()
    elseif action ==# 'normal-wrong-window'
      source.QueueRegistrationResult(dictionary.Candidate.new('不正', []))
    elseif action =~# '^normal-'
      if child_text_override != ''
        setline(1, split(child_text_override, "\n", true))
      endif
      if action ==# 'normal-external'
        setbufline(source_buffer, 1, '外部変更')
      endif
      const text = ReturnToSource()
      if action ==# 'normal-external-on-enter'
        execute 'autocmd caskk_test_registration_return InsertEnter <buffer=' .. source_buffer .. '> ++once MutateOnReturn()'
      elseif action ==# 'normal-disable'
        execute 'autocmd caskk_test_registration_return InsertEnter <buffer=' .. source_buffer .. '> ++once CountReturn()'
      endif
      var candidate: dictionary.Candidate = null_object
      if action !=# 'normal-cancel'
        candidate = dictionary.Candidate.new(text, ['復帰注釈'])
      endif
      source.QueueRegistrationResult(candidate)
      if action ==# 'normal-duplicate'
        source.QueueRegistrationResult(dictionary.Candidate.new('不正', []))
      elseif action ==# 'normal-disable'
        source.Disable()
      endif
    else
      if action ==# 'external'
        setbufline(source_buffer, 1, '外部変更')
      endif
      const text = ReturnToSource()
      if action ==# 'disable'
        source.Disable()
        return
      endif
      if action ==# 'guard'
        for attempted in ['native', 'input', 'register', 'enter']
          AttemptSuspendedInput(attempted)
        endfor
        RecordSource()
      endif
      source.ResumeRegistration()
      if action ==# 'cancel'
        source.CancelRegistration()
      else
        source.CompleteRegistration(text)
      endif
    endif
  catch
    errors->add(v:exception)
  endtry
enddef

defcompile Handle

def Setup(): list<number>
  const previous = bufnr('%')
  source_buffer = bufadd('')
  bufload(source_buffer)
  execute 'noautocmd keepalt hide buffer ' .. source_buffer
  source_window = win_getid()
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  child = null_object
  child_window = 0
  child_buffer = 0
  errors = []
  source_texts = []
  suspended = []
  highlight_counts = []
  child_text_override = ''
  return_insertions = 0
  preferences = user_state.State.new()
  compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [scheme.SpecialDefinition.new(['d'], '漢字')])
  source = binding.Binding.new(compiled, '', {}, preferences, {s: 'StartConversion'})
  source.Enable()
  inoremap <buffer> <F3> <ScriptCmd>Handle('open')<CR>
  return [previous, source_buffer]
enddef

def Cleanup(context: list<number>)
  execute 'autocmd! caskk_test_registration_return * <buffer=' .. source_buffer .. '>'
  if child isnot null_object && child.IsEnabled()
    win_gotoid(child_window)
    child.Disable()
  endif
  if child_window > 0 && win_id2win(child_window) > 0
    win_execute(child_window, 'close!')
  endif
  win_gotoid(source_window)
  try
    source.Disable()
  catch
    if v:exception !=# 'caskk: buffer changed outside the managed undo unit'
      throw v:exception
    endif
  endtry
  execute 'noautocmd keepalt hide buffer ' .. context[0]
  execute 'silent! bwipeout! ' .. context[1]
  if child_buffer > 0 && bufexists(child_buffer)
    execute 'silent! bwipeout! ' .. child_buffer
  endif
enddef

suite.registration_survives_child_ime_input_and_keeps_original_undo_boundaries = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F3>d\<F4>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(source_texts, ['前か後'])
  assert.equals(suspended, [true])
  assert.equals(highlight_counts, [1])
  assert.equals(getline(1), '前漢字か後')
  assert.equals(source.GetRegistrationRequest() is null_object, true)
  assert.equals(preferences.GetSnapshot().entries[json_encode(['か', ''])][0].text, '漢字')
  assert.equals(bufexists(child_buffer), 0)
  for expected in ['前漢字後', '前か後', '前後']
    normal! u
    assert.equals(getline(1), expected)
  endfor
}

suite.cancellation_after_window_switch_preserves_reading_without_learning = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const before = codec.Encode(preferences.GetSnapshot())
  feedkeys("aKas\<F3>d\<F5>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前かか後')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  assert.equals(bufexists(child_buffer), 0)
}

suite.preedit_without_registration_request_cannot_be_suspended = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKa\<F3>ka\<Esc>", 'xt')
  assert.equals(errors, ['caskk: no current dictionary registration request'])
  assert.equals(getline(1), '前かか後')
  assert.equals(child_window, 0)
}

suite.suspended_input_and_native_motion_are_rejected_until_resumed = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F3>d\<F7>\<Esc>", 'xt')
  assert.equals(errors, repeat(['caskk: input is suspended for dictionary registration'], 4))
  assert.equals(source_texts, ['前か後', '前か後'])
  assert.equals(suspended, [true, true])
  assert.equals(getline(1), '前漢字後')
  const candidates = preferences.GetSnapshot().entries[json_encode(['か', ''])]
  assert.equals(len(candidates), 1)
  assert.equals(candidates[0].text, '漢字')
}

suite.resume_from_another_window_fails_without_consuming_the_request = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F3>d\<F6>\<F4>\<Esc>", 'xt')
  assert.equals(errors, ['caskk: binding target must be the current buffer'])
  assert.equals(getline(1), '前漢字後')
}

suite.external_edit_blocks_resume_before_registration_changes_user_state = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const before = codec.Encode(preferences.GetSnapshot())
  feedkeys("aKas\<F3>d\<F8>\<Esc>", 'xt')
  assert.equals(errors, ['caskk: buffer changed outside the managed undo unit'])
  assert.equals(getline(1), '外部変更')
  assert.equals(source.GetEditor().IsRegistrationSuspended(), true)
  assert.equals(source.GetRegistrationRequest().reading, 'か')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.explicit_disable_closes_a_suspended_session_and_restores_native_input = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const before = codec.Encode(preferences.GetSnapshot())
  feedkeys("aKas\<F3>d\<F9>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前かka後')
  assert.equals(source.IsEnabled(), false)
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.normal_mode_return_completes_before_following_input_in_the_middle_of_a_line = (): void => {
  const context = Setup()
  defer Cleanup(context)
  nnoremap <buffer> i x
  feedkeys("aKas\<F3>d\<Esc>\<F4>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前漢字か後')
  assert.equals(preferences.GetSnapshot().entries[json_encode(['か', ''])][0].annotations, ['復帰注釈'])
  for expected in ['前漢字後', '前か後', '前後']
    normal! u
    assert.equals(getline(1), expected)
  endfor
}

suite.normal_mode_return_appends_at_the_original_multibyte_end_of_line = (): void => {
  const context = Setup()
  defer Cleanup(context)
  setline(1, '前')
  feedkeys("aKas\<F3>d\<Esc>\<F4>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前漢字か')
}

suite.normal_mode_return_restores_the_tracked_line_number = (): void => {
  const context = Setup()
  defer Cleanup(context)
  setline(1, ['上', '前後'])
  cursor(2, 1)
  feedkeys("aKas\<F3>d\<Esc>\<F4>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1, '$'), ['上', '前漢字か後'])
}

suite.normal_mode_cancellation_returns_to_editable_reading_without_learning = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const before = codec.Encode(preferences.GetSnapshot())
  feedkeys("aKas\<F3>d\<Esc>\<F5>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前かか後')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  normal! u
  assert.equals(getline(1), '前後')
}

suite.queued_registration_text_is_not_interpreted_as_commands_or_keycodes = (): void => {
  const context = Setup()
  defer Cleanup(context)
  child_text_override = "字'\"<BS>\n次"
  feedkeys("aKas\<F3>d\<Esc>\<F4>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1, '$'), ["前字'\"<BS>", '次か後'])
  const stored = preferences.GetSnapshot().entries[json_encode(['か', ''])][0]
  assert.equals(stored.text, child_text_override)
  assert.equals(stored.annotations, ['復帰注釈'])
}

suite.queuing_from_the_wrong_window_does_not_consume_the_request = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F3>d\<Esc>\<F6>\<F4>\<Esc>", 'xt')
  assert.equals(errors, ['caskk: binding target must be the current buffer'])
  assert.equals(getline(1), '前漢字後')
}

suite.external_edit_before_queuing_is_rejected_without_registering = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const before = codec.Encode(preferences.GetSnapshot())
  feedkeys("aKas\<F3>d\<Esc>\<F8>", 'xt')
  assert.equals(errors, ['caskk: buffer changed outside the managed undo unit'])
  assert.equals(getline(1), '外部変更')
  assert.equals(source.GetEditor().IsRegistrationSuspended(), true)
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.external_edit_on_insert_enter_is_rechecked_before_applying_the_result = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const before = codec.Encode(preferences.GetSnapshot())
  try
    feedkeys("aKas\<F3>d\<Esc>\<F10>", 'xt')
  catch
    errors->add(v:exception)
    feedkeys("\<Esc>", 'nx')
  endtry
  assert.equals(errors, ['caskk: buffer changed outside the managed undo unit'])
  assert.equals(getline(1), '外部変更')
  assert.equals(source.GetEditor().IsRegistrationSuspended(), true)
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.duplicate_queued_reply_is_rejected_and_the_first_reply_is_preserved = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F3>d\<Esc>\<F7>\<Esc>", 'xt')
  assert.equals(errors, ['caskk: registration result is already queued'])
  assert.equals(getline(1), '前漢字後')
  const candidates = preferences.GetSnapshot().entries[json_encode(['か', ''])]
  assert.equals(len(candidates), 1)
  assert.equals(candidates[0].text, '漢字')
}

suite.disabling_before_queued_return_does_not_reenter_insert_or_register = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const before = codec.Encode(preferences.GetSnapshot())
  feedkeys("aKas\<F3>d\<Esc>\<F9>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前か後')
  assert.equals(return_insertions, 0)
  assert.equals(source.IsEnabled(), false)
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.queued_reply_also_completes_when_already_back_in_insert_mode = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F3>d\<F10>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前漢字か後')
  assert.equals(preferences.GetSnapshot().entries[json_encode(['か', ''])][0].text, '漢字')
}
