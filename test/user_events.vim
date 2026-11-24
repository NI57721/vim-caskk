vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime

const suite = themis#suite('Caskk User events')
const assert = themis#helper('assert')
const EVENTS = ['Enable', 'Disable', 'InputModeChanged', 'PreeditStart', 'PreeditEnd',
  'ConversionStart', 'ConversionEnd', 'CompletionStart', 'CompletionEnd',
  'RegistrationStart', 'RegistrationEnd']
var previous: number
var parent: number
var path: string
var snapshot: user_state.Snapshot
var events: list<list<any>>

def Capture(event: string)
  events->add([event, getline(1), bufnr('%'), Caskk.IsEnabled(), len(popup_list()), maparg('k', 'i'), maparg('<F4>', 'i')])
enddef

def Enable()
  Caskk.Enable('user-events')
enddef

def Setup(options: dict<any> = {})
  previous = bufnr('%')
  parent = bufadd('')
  bufload(parent)
  execute 'noautocmd keepalt hide buffer ' .. parent
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  path = tempname()
  writefile(['か /蚊/科/課/', 'かな /仮名/', 'かなた /彼方/'], path)
  Caskk.RegisterInputScheme({name: 'user-events', consonants: {k: 'k', n: 'n'},
    combinations: {a: 'a'}, specials: {z: '登録'}})
  Caskk.Config(extend({dictionaries: [path], candidate_select_keys: ['1', '2'],
    mode_popup: false, candidate_popup: true, completion_min_length: 2,
    registration_prefill: false, mappings: {s: 'Convert', "\<F6>": 'NextCandidate', c: 'Commit',
      r: 'OpenRegistration', q: 'KatakanaMode', "\<F5>": 'CancelCompletion'}}, options))
  events = []
  augroup caskk_test_user_events
    autocmd!
  augroup END
  for name in EVENTS
    execute 'autocmd caskk_test_user_events User Caskk' .. name .. ' Capture(' .. string(name) .. ')'
  endfor
  inoremap <buffer> <F7> <ScriptCmd>Caskk.Disable()<CR>
  nnoremap <buffer> <F12> <ScriptCmd>Caskk.Reconvert()<CR>
  cnoremap <F12> <ScriptCmd>Enable()<CR>
enddef

def Cleanup()
  autocmd! caskk_test_user_events
  cunmap <F12>
  Caskk.Disable()
  Caskk.Config({})
  user_runtime.Get().Restore(snapshot)
  execute 'noautocmd keepalt hide buffer ' .. previous
  execute 'silent! bwipeout! ' .. parent
  delete(path)
enddef

def Check(expected: list<list<string>>)
  assert.equals(mapnew(events, (_, item) => item[: 1]), expected)
  assert.equals(mapnew(events, (_, item) => item[2]), repeat([parent], len(events)))
enddef

suite.conversion_escape_labels_commit_and_mode_changes = (): void => {
  Setup()
  defer Cleanup()
  Enable()
  Enable()
  feedkeys("aKas2\<F6>\<Esc>scqq\<Esc>", 'xt')
  Caskk.Disable()
  Caskk.Disable()
  Check([['Enable', '前後'], ['PreeditStart', '前か後'], ['ConversionStart', '前蚊後'],
    ['ConversionEnd', '前か後'], ['ConversionStart', '前蚊後'],
    ['ConversionEnd', '前蚊後'], ['PreeditEnd', '前蚊後'],
    ['InputModeChanged', '前蚊後'], ['InputModeChanged', '前蚊後'], ['Disable', '前蚊後']])
  assert.equals(events[0][3], true)
  assert.equals(events[-1][3], false)
  assert.match(events[0][5], 'DispatchInput')
  assert.equals(events[-1][5], '')
}

suite.disabled_reconversion_reports_the_preview_and_commit = (): void => {
  Setup()
  defer Cleanup()
  Enable()
  feedkeys("aKasc\<Esc>", 'xt')
  Caskk.Disable()
  events = []
  cursor(1, 4)
  feedkeys("\<F12>2c\<Esc>", 'xt')
  Check([['PreeditStart', '前蚊後'], ['ConversionStart', '前蚊後'],
    ['ConversionEnd', '前科後'], ['PreeditEnd', '前科後']])
  assert.equals(events[0][3], false)
}

suite.asynchronous_completion_reports_display_and_cancel = (): void => {
  Setup()
  defer Cleanup()
  Enable()
  events = []
  feedkeys("aKana\<Cmd>sleep 30m\<CR>\<F5>\<Esc>", 'xt')
  Check([['PreeditStart', '前か後'], ['CompletionStart', '前かな後'],
    ['CompletionEnd', '前かな後'], ['PreeditEnd', '前かな後']])
  assert.equals(events[1][4], 1)
  assert.equals(events[2][4], 0)
}

suite.registration_notifies_in_parent_after_open_and_after_result = (): void => {
  for inline in [true, false]
    for cancel in [true, false]
      Setup({registration_inline: inline})
      try
        Enable()
        events = []
        feedkeys("aKas\<F6>\<F6>rqKa" .. (cancel ? "\<Esc>" : "zz\<CR>") .. "\<Esc>", 'xt')
        assert.equals(mapnew(events, (_, item) => item[0]), cancel
          ? ['PreeditStart', 'ConversionStart', 'ConversionEnd', 'RegistrationStart',
            'RegistrationEnd', 'ConversionStart', 'ConversionEnd', 'PreeditEnd']
          : ['PreeditStart', 'ConversionStart', 'ConversionEnd', 'RegistrationStart',
            'RegistrationEnd', 'PreeditEnd'], string([inline, cancel, events]))
        assert.equals(mapnew(events, (_, item) => item[2]), repeat([parent], len(events)))
        assert.equals(events[4][1], cancel ? '前課後' : getline(1))
        assert.equals(events[3][6], inline ? '<Nop>' : '')
        assert.equals(events[4][6], '')
      finally
        Cleanup()
      endtry
    endfor
  endfor
}

suite.failed_activation_commandline_and_unsubscribed_operations_are_quiet = (): void => {
  const invalid_state = tempname()
  defer delete(invalid_state)
  writefile(['invalid state data'], invalid_state)
  Setup({state_auto: true, state_path: invalid_state})
  defer Cleanup()
  var failure = ''
  try
    Enable()
  catch
    failure = v:exception
  endtry
  assert.match(failure, 'caskk:')
  assert.equals(Caskk.IsEnabled(), false)
  assert.equals(events, [])
  Caskk.Config({})
  feedkeys(":\<F12>Ka\<C-C>", 'xt')
  assert.equals(events, [])
  autocmd! caskk_test_user_events
  const errmsg = v:errmsg
  Enable()
  feedkeys("aKa\<Esc>", 'xt')
  Caskk.Disable()
  assert.equals(v:errmsg, errmsg)
}


suite.empty_completion_and_wildcard_subscriptions = (): void => {
  Setup()
  defer Cleanup()
  autocmd! caskk_test_user_events
  autocmd caskk_test_user_events User Caskk* Capture(expand('<amatch>'))
  Enable()
  feedkeys("aNana\<Cmd>sleep 30m\<CR>\<Esc>", 'xt')
  Caskk.Disable()
  Check([['CaskkEnable', '前後'], ['CaskkPreeditStart', '前な後'],
    ['CaskkPreeditEnd', '前なな後'], ['CaskkDisable', '前なな後']])
}


suite.disable_ends_completion_and_preedit_before_notifying = (): void => {
  Setup()
  defer Cleanup()
  Enable()
  events = []
  feedkeys("aKana\<Cmd>sleep 30m\<CR>\<F7>\<Esc>", 'xt')
  Check([['PreeditStart', '前か後'], ['CompletionStart', '前かな後'],
    ['CompletionEnd', '前かな後'], ['PreeditEnd', '前かな後'], ['Disable', '前かな後']])
  assert.equals(events[2][5], '')
}

suite.disabled_reconversion_registration_does_not_enable_input = (): void => {
  for inline in [true, false]
    Setup({registration_inline: inline, registration_auto: true})
    try
      Enable()
      feedkeys("aKasc\<Esc>", 'xt')
      Caskk.Disable()
      events = []
      cursor(1, 4)
      feedkeys("\<F12>\<F6>\<F6>z\<CR>\<Esc>", 'xt')
      Check([['PreeditStart', '前蚊後'], ['ConversionStart', '前蚊後'],
        ['ConversionEnd', '前か後'], ['RegistrationStart', '前か後'],
        ['RegistrationEnd', '前登録後'], ['PreeditEnd', '前登録後']])
      assert.equals(mapnew(events, (_, item) => item[3]), repeat([false], len(events)))
    finally
      Cleanup()
    endtry
  endfor
}
