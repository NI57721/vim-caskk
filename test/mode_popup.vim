vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime

final suite = themis#suite('input mode popup')
const assert = themis#helper('assert')

var captures: list<list<list<string>>> = []
var capture_positions: list<list<list<number>>> = []
var capture_cursor_positions: list<list<number>> = []
var previous_buffer = 0
var test_buffer = 0
var previous_user_state: user_state.Snapshot = null_object

def g:CaskkTestModePopupCapture()
  redraw
  final popup_lines: list<list<string>> = []
  var positions: list<list<number>> = []
  for id in popup_list()
    if !empty(popup_getpos(id))
      const lines = getbufline(winbufnr(id), 1, '$')
      popup_lines->add(lines)
      const position = popup_getpos(id)
      positions->add([position.line, position.col])
    endif
  endfor
  captures->add(popup_lines)
  capture_positions->add(positions)
  const cursor_position = screenpos(win_getid(), line('.'), col('.'))
  capture_cursor_positions->add([cursor_position.row, cursor_position.col])
enddef

def g:CaskkTestModePopupCaptureAfterDelay()
  sleep 20m
  g:CaskkTestModePopupCapture()
enddef

def g:CaskkTestModePopupCaptureAfterTimeout()
  sleep 1100m
  g:CaskkTestModePopupCapture()
enddef

def Setup(options: dict<any> = {}): void
  previous_user_state = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
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
  capture_positions = []
  capture_cursor_positions = []
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
    user_runtime.Get().Restore(previous_user_state)
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

suite.mode_popup_shows_on_insert_enter_before_any_input = (): void => {
  Setup({mode_popup_time: 0})
  defer Cleanup()
  feedkeys("i\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['あ']]])
  assert.equals(getline(1), '前後')
}

suite.mode_popup_remains_visible_after_the_first_character = (): void => {
  Setup({mode_popup_labels: {katakana: 'カナ'}, mode_popup_time: 10000})
  defer Cleanup()
  feedkeys("a\<F1>.\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['カナ']]])
  assert.equals(getline(1), '前.後')
  assert.equals(capture_positions, [[[2, 4]]])
}

suite.mode_popup_is_visible_immediately_after_native_newline = (): void => {
  Setup({mode_popup_labels: {katakana: 'カナ'}, mode_popup_time: 10000})
  defer Cleanup()
  feedkeys("a\<F1>\<CR>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['カナ']]])
  assert.equals(getline(1, '$'), ['前', '後'])
}

suite.default_hiragana_popup_is_visible_after_native_newline = (): void => {
  Setup({mode_popup_time: 0})
  defer Cleanup()
  feedkeys("a\<CR>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['あ']]])
  assert.equals(getline(1, '$'), ['前', '後'])
}

suite.mode_popup_returns_after_native_backspace = (): void => {
  Setup({mode_popup_time: 0})
  defer Cleanup()
  feedkeys("a\<BS>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['あ']]])
}

suite.mode_popup_returns_after_native_delete = (): void => {
  Setup({mode_popup_time: 0})
  defer Cleanup()
  feedkeys("a\<Del>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['あ']]])
}

suite.mode_popup_returns_after_native_cursor_motion = (): void => {
  Setup({mode_popup_time: 0})
  defer Cleanup()
  feedkeys("a\<Right>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['あ']]])
}

suite.mode_popup_returns_after_action_mapped_native_keys = (): void => {
  Setup({mode_popup_time: 0, mappings: {
    "\<Up>": 'PreviousCandidate', "\<Down>": 'Convert',
    "\<BS>": 'DeleteUserEntry', "\<CR>": 'Commit'}})
  defer Cleanup()
  setline(1, ['前後', '別行'])
  feedkeys("a\<Up>\<F12>\<Down>\<F12>\<BS>\<F12>\<CR>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['あ']], [['あ']], [['あ']], [['あ']]])
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

suite.mode_popup_follows_horizontal_motion_inside_preedit = (): void => {
  Setup({sticky_key: ';', mode_popup_time: 0})
  defer Cleanup()
  feedkeys("a;ka\<Left>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['▽あ']]])
  assert.equals(capture_positions, [[[2, 3]]])
  assert.equals(capture_cursor_positions, [[1, 3]])
}

suite.sticky_key_alone_shows_the_modified_mode_marker = (): void => {
  Setup({sticky_key: ';', mode_popup_time: 0})
  defer Cleanup()
  feedkeys("a;\<F12>\<Esc>", 'xt')
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

suite.default_mode_popup_stays_visible_after_the_initial_timeout = (): void => {
  Setup()
  defer Cleanup()
  inoremap <buffer> <F12> <Cmd>call CaskkTestModePopupCaptureAfterTimeout()<CR>
  feedkeys("a\<F1>\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['ア']]])
  assert.equals(popup_list(), [])
}

suite.mode_popup_follows_the_cursor_during_preedit_input = (): void => {
  Setup({mode_popup_time: 0})
  defer Cleanup()
  feedkeys("aKa\<F12>ka\<F12>ka\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['▽あ']], [['▽あ']], [['▽あ']]])
  assert.equals(capture_cursor_positions, [[1, 5], [1, 7], [1, 9]])
  assert.equals(capture_positions, [[[2, 5]], [[2, 7]], [[2, 9]]])
}

suite.mode_popup_returns_after_cursor_movement_and_stays_visible = (): void => {
  Setup()
  defer Cleanup()
  inoremap <buffer> <F12> <Cmd>call CaskkTestModePopupCaptureAfterTimeout()<CR>
  feedkeys("aKa\<F12>ka\<F12>\<Esc>", 'xt')
  assert.equals(captures, [[['▽あ']], [['▽あ']]])
}
