vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime

final suite = themis#suite('in-buffer dictionary registration')
const assert = themis#helper('assert')
var previous_state: user_state.Snapshot = null_object

def Setup(): list<number>
  previous_state = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  Caskk.Config({registration_auto: false, registration_inline: true,
    registration_prefill: false, mappings: {s: 'Convert', "\<F6>": 'OpenRegistration'}})
  Caskk.RegisterInputScheme({name: 'registration-inline', consonants: {k: 'k'},
    combinations: {a: 'a'}, specials: {z: '漢字'}})
  Caskk.Enable('registration-inline')
  return [previous, number, win_getid()]
enddef

def Cleanup(context: list<number>)
  try
    Caskk.Disable()
    Caskk.Config({})
  finally
    execute 'noautocmd keepalt hide buffer ' .. context[0]
    execute 'silent! bwipeout! ' .. context[1]
    user_runtime.Get().Restore(previous_state)
  endtry
enddef

suite.registration_input_stays_in_the_original_buffer_and_window = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const popups = popup_list()
  feedkeys("aKas\<F6>z\<CR>\<Esc>", 'xt')
  assert.equals(bufnr('%'), context[1])
  assert.equals(win_getid(), context[2])
  assert.equals(winnr('$'), 1)
  assert.equals(popup_list(), popups)
  assert.equals(getline(1), '前漢字後')
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
}

suite.cancelling_inline_registration_restores_editable_reading_without_learning = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>z\<Esc>", 'xt')
  assert.equals(popup_list(), [])
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
  feedkeys("aka\<Esc>", 'xt')
  assert.equals(bufnr('%'), context[1])
  assert.equals(win_getid(), context[2])
  assert.equals(winnr('$'), 1)
  assert.equals(getline(1), '前かか後')
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
  assert.equals(user_runtime.Get().GetSnapshot().entries, {})
}
