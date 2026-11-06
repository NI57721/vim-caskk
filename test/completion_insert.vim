vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime

final suite = themis#suite('Insert reading completion')
const assert = themis#helper('assert')
var captures: list<string> = []
var popup_lines: list<list<string>> = []
var previous = 0
var target = 0
var dictionary_path = ''
var snapshot: user_state.Snapshot = null_object

def Capture()
  captures->add(getline(1))
  final lines: list<string> = []
  for id in popup_list()
    lines->extend(getbufline(winbufnr(id), 1, '$'))
  endfor
  popup_lines->add(lines)
enddef

def Setup(options: dict<any> = {})
  previous = bufnr('%')
  target = bufadd('')
  bufload(target)
  execute 'noautocmd keepalt hide buffer ' .. target
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  dictionary_path = tempname()
  writefile(['かな /仮名;文字/', 'かなた /彼方/', 'かなもの /金物/'], dictionary_path)
  Caskk.RegisterInputScheme({name: 'completion-test', consonants: {k: 'k', n: 'n'},
    combinations: {a: 'a', i: 'i'}})
  Caskk.Config(extend({dictionaries: [dictionary_path], completion_min_length: 2,
    mappings: {"\<Tab>": 'ShowCompletion', "\<F5>": 'CancelCompletion', "\<Space>": 'Convert'}}, options))
  inoremap <buffer> <F12> <ScriptCmd>Capture()<CR>
  captures = []
  popup_lines = []
  Caskk.Enable('completion-test')
enddef

def Cleanup()
  Caskk.Disable()
  Caskk.Config({})
  user_runtime.Get().Restore(snapshot)
  execute 'noautocmd keepalt hide buffer ' .. previous
  execute 'silent! bwipeout! ' .. target
  delete(dictionary_path)
enddef

suite.menu_keeps_reading_and_enter_commits_the_selected_word = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<Tab>\<F12>\<Tab>\<F12>\<CR>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前かな後', '前彼方後'])
  assert.equals(index(popup_lines[0], '▶ 1/3 仮名 — 文字 / 読み: かな') >= 0, true)
  assert.equals(index(popup_lines[1], '▶ 2/3 彼方 — 読み: かなた') >= 0, true)
  assert.equals(len(popup_lines[2]), 1)
  assert.equals(popup_list(), [])
  normal! u
  assert.equals(getline(1), '前かな後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.cancel_backspace_and_native_movement_do_not_accept_completion = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<Tab>\<F5>\<F12>\<Tab>\<BS>\<F12>\<Tab>\<Left>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前かな後'])
  assert.equals(getline(1), '前かな後')
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.arrow_navigation_accepts_directly_without_inserting_a_newline = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<Tab>\<Down>\<Down>\<Up>\<CR>\<Esc>", 'xt')
  assert.equals(getline(1), '前彼方後')
}

suite.no_match_short_reading_and_unfinished_keys_do_not_start_conversion = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKa\<Tab>\<F12>ki\<Tab>\<F12>k\<Tab>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前か後', '前かき後', '前かきk後'])
  for lines in popup_lines
    assert.equals(len(lines), 1)
  endfor
}

suite.accepted_completion_is_one_commit_with_undo_reading_disabled = (): void => {
  Setup({undo_revert_to_reading: false})
  defer Cleanup()
  feedkeys("aKana\<Tab>\<CR>\<Esc>", 'xt')
  assert.equals(getline(1), '前仮名後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.typing_and_conversion_close_the_completion_menu = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<Tab>ki\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かなき後'])
  assert.equals(len(popup_lines[0]), 1)
  feedkeys("aKana\<Tab> \<F12>\<CR>\<Esc>", 'xt')
  assert.equals(index(popup_lines[1], '▶ 1/1 仮名 — 文字') >= 0, true)
}

suite.popup_can_be_disabled_without_disabling_completion = (): void => {
  Setup({candidate_popup: false})
  defer Cleanup()
  feedkeys("aKana\<Tab>\<F12>\<CR>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後'])
  assert.equals(len(popup_lines[0]), 1)
  assert.equals(getline(1), '前仮名後')
}

suite.completion_is_visible_in_a_real_terminal = (): void => {
  Setup()
  defer Cleanup()
  const script = tempname() .. '.vim'
  const ready = tempname()
  defer delete(script)
  defer delete(ready)
  writefile([
    'vim9script',
    'set rtp^=' .. escape(getcwd(), ' ,'),
    "import autoload 'caskk.vim' as C",
    "C.RegisterInputScheme({name: 'visible', consonants: {k: 'k', n: 'n'}, combinations: {a: 'a'}})",
    'C.Config({mode_popup_time: 0, dictionaries: [' .. string(dictionary_path)
      .. '], mappings: {"\<Tab>": "ShowCompletion"}})',
    "C.Enable('visible')",
    'writefile(["ready"], ' .. string(ready) .. ')',
  ], script)
  const terminal = term_start([v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-N', '-S', script],
    {hidden: true, term_rows: 12, term_cols: 50})
  try
    for _ in range(100)
      term_wait(terminal, 10)
      if filereadable(ready)
        break
      endif
    endfor
    term_sendkeys(terminal, "iKana\<Tab>")
    term_wait(terminal, 100)
    assert.equals(trim(term_getline(terminal, 1)), 'かな')
    const screen = join(mapnew(range(2, 11), (_, row) => term_getline(terminal, row)), "\n")
    assert.equals(stridx(screen, '▶ 1/3 仮名') >= 0, true)
    term_sendkeys(terminal, "\<Tab>\<CR>")
    term_wait(terminal, 100)
    assert.equals(trim(term_getline(terminal, 1)), '彼方')
  finally
    job_stop(term_getjob(terminal), 'kill')
    execute 'silent! bwipeout! ' .. terminal
  endtry
}
