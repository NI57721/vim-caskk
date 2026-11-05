vim9script

import autoload 'caskk.vim' as Caskk

final suite = themis#suite('input mode popup')
const assert = themis#helper('assert')

var captures: list<list<list<string>>> = []
var previous_buffer = 0
var test_buffer = 0

def g:CaskkTestModePopupCapture()
  final popup_lines: list<list<string>> = []
  for id in popup_list()
    popup_lines->add(getbufline(winbufnr(id), 1, '$'))
  endfor
  captures->add(popup_lines)
enddef

def g:CaskkTestModePopupCaptureAfterDelay()
  sleep 20m
  g:CaskkTestModePopupCapture()
enddef

def Setup(options: dict<any> = {}): void
  previous_buffer = bufnr('%')
  test_buffer = bufadd('')
  bufload(test_buffer)
  execute 'noautocmd keepalt hide buffer ' .. test_buffer
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  Caskk.Config({})
  Caskk.RegisterInputScheme({name: 'mode-popup-test', consonants: {k: 'k'},
    combinations: {a: 'a'}})
  captures = []
  inoremap <buffer> <F12> <Cmd>call CaskkTestModePopupCapture()<CR>
  Caskk.Config(extend({mappings: {"\<F1>": 'KatakanaMode', "\<F2>": 'AbbreviationMode',
    "\<Space>": 'Convert', "\<F3>": 'Commit'}}, options))
  Caskk.Enable('mode-popup-test')
enddef

def Cleanup()
  try
    Caskk.Disable()
    Caskk.Config({})
  finally
    execute 'noautocmd keepalt hide buffer ' .. previous_buffer
    execute 'silent! bwipeout! ' .. test_buffer
  endtry
enddef

suite.mode_switches_show_the_configured_label_near_the_insert_cursor = (): void => {
  Setup({mode_popup_labels: {katakana: 'カナ'}, mode_popup_time: 10000})
  defer Cleanup()
  feedkeys("a\<F1>\<F12>a\<Esc>", 'xt')
  assert.equals(captures, [[['カナ']]])
  assert.equals(getline(1), '前ア後')
}

suite.abbreviation_commit_updates_the_popup_to_the_restored_mode = (): void => {
  const dictionary = tempname()
  defer delete(dictionary)
  writefile(['apple /アップル/'], dictionary)
  Setup({dictionaries: [dictionary], mode_popup_time: 10000})
  defer Cleanup()
  feedkeys("a\<F1>\<F2>apple\<Space>\<F3>\<F12>\<Esc>", 'xt')
  assert.equals(captures[-1], [['ア']])
  assert.equals(getline(1), '前アップル後')
}

suite.candidate_popup_replaces_the_transient_mode_popup = (): void => {
  const dictionary = tempname()
  defer delete(dictionary)
  writefile(['か /蚊/家/'], dictionary)
  Setup({dictionaries: [dictionary], mode_popup_time: 10000})
  defer Cleanup()
  feedkeys("aKa\<Space>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['▼あ'], ['▶ 1/2 蚊', '  2/2 家']]])
}

suite.modified_preedit_prefixes_the_mode_label_with_start_marker = (): void => {
  Setup({mode_popup_time: 10000})
  defer Cleanup()
  feedkeys("aKa\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['▽あ']]])
}

suite.candidate_selection_prefixes_the_mode_label_with_candidate_marker = (): void => {
  const dictionary = tempname()
  defer delete(dictionary)
  writefile(['か /蚊/'], dictionary)
  Setup({candidate_popup: false, dictionaries: [dictionary], mode_popup_time: 10000})
  defer Cleanup()
  feedkeys("aKa\<Space>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['▼あ']]])
}

suite.modified_and_candidate_markers_can_be_customized = (): void => {
  const dictionary = tempname()
  defer delete(dictionary)
  writefile(['か /蚊/'], dictionary)
  Setup({dictionaries: [dictionary], mode_popup_markers: {modified: '＊', candidate: '●'},
    mode_popup_time: 10000})
  defer Cleanup()
  feedkeys("aKa\<F12>\<Space>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['＊あ']], [['●あ'], ['▶ 1/1 蚊']]])
}

suite.disabled_mode_popup_creates_no_popup = (): void => {
  Setup({mode_popup: false})
  defer Cleanup()
  feedkeys("a\<F1>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[]])
}

suite.leaving_insert_mode_closes_the_mode_popup = (): void => {
  Setup({mode_popup_time: 10000})
  defer Cleanup()
  feedkeys("a\<F1>\<Esc>", 'xt')
  assert.equals(popup_list(), [])
}

suite.zero_timeout_keeps_the_mode_popup_until_session_cleanup = (): void => {
  Setup({mode_popup_time: 0})
  defer Cleanup()
  inoremap <buffer> <F12> <Cmd>call CaskkTestModePopupCaptureAfterDelay()<CR>
  feedkeys("a\<F1>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['ア']]])
  assert.equals(popup_list(), [])
}
