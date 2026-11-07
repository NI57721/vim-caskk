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
const WAIT = "\<Cmd>sleep 30m\<CR>"

def Capture()
  sleep 30m
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
  writefile(['かな /仮名;文字/', 'かなた /彼方/', 'かなもの /金物/',
    'apple /林檎/', 'application /アプリ/', 'ABC123 /英数字/'], dictionary_path)
  Caskk.RegisterInputScheme({name: 'completion-test', consonants: {k: 'k', n: 'n', t: 't'},
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
  feedkeys("aKana\<F12>\<Tab>\<F12>\<CR>\<F12>\<Esc>", 'xt')
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
  feedkeys("aKana\<F5>\<F12>\<Tab>\<BS>\<F12>\<Tab>\<Left>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前か後'])
  assert.equals(getline(1), '前か後')
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.arrow_navigation_accepts_directly_without_inserting_a_newline = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana" .. WAIT .. "\<Down>\<Down>\<Up>\<CR>\<Esc>", 'xt')
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
  feedkeys("aKana" .. WAIT .. "\<CR>\<Esc>", 'xt')
  assert.equals(getline(1), '前仮名後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.typing_and_conversion_close_the_completion_menu = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKanaki\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かなき後'])
  assert.equals(len(popup_lines[0]), 1)
  feedkeys("aKana \<F12>\<CR>\<Esc>", 'xt')
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
    term_sendkeys(terminal, "iKana")
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

suite.automatic_completion_requires_no_show_completion_mapping = (): void => {
  Setup({mappings: {"\<Space>": 'Convert'}})
  defer Cleanup()
  feedkeys("aKa\<F12>na\<F12>\<CR>\<Esc>", 'xt')
  assert.equals(captures, ['前か後', '前かな後'])
  assert.equals(len(popup_lines[0]), 1)
  assert.equals(index(popup_lines[1], '▶ 1/3 仮名 — 文字 / 読み: かな') >= 0, true)
  assert.equals(getline(1), '前仮名後')
  normal! u
  assert.equals(getline(1), '前かな後')
}

suite.automatic_completion_refreshes_after_typing_and_hides_for_pending_input = (): void => {
  Setup({sticky_key: ';'})
  defer Cleanup()
  feedkeys("aKana\<F12>t\<F12>a\<F12>;\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前かなt後', '前かなた後', '前かなた後'])
  assert.equals(index(popup_lines[0], '▶ 1/3 仮名 — 文字 / 読み: かな') >= 0, true)
  assert.equals(len(popup_lines[1]), 1)
  assert.equals(index(popup_lines[2], '▶ 1/1 彼方 — 読み: かなた') >= 0, true)
  assert.equals(len(popup_lines[3]), 1)
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.automatic_completion_uses_the_configured_minimum_and_returns_after_editing = (): void => {
  Setup({completion_min_length: 3, mappings: {c: 'CancelCompletion', "\<Space>": 'Convert'}})
  defer Cleanup()
  feedkeys("aKana\<F12>ta\<F12>c\<BS>\<F12>ta\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前かなた後', '前かな後', '前かなた後'])
  assert.equals(len(popup_lines[0]), 1)
  assert.equals(index(popup_lines[1], '▶ 1/1 彼方 — 読み: かなた') >= 0, true)
  assert.equals(len(popup_lines[2]), 1)
  assert.equals(index(popup_lines[3], '▶ 1/1 彼方 — 読み: かなた') >= 0, true)
}

suite.hidden_candidate_popup_does_not_automatically_select_completion = (): void => {
  Setup({candidate_popup: false})
  defer Cleanup()
  feedkeys("aKana\<F12>\<CR>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後'])
  assert.equals(getline(1), '前かな')
  assert.equals(getline(2), '後')
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.backspace_deletes_reading_and_refreshes_automatic_completion = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKanata\<F12>\<BS>\<F12>\<BS>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かなた後', '前かな後', '前か後'])
  assert.equals(index(popup_lines[0], '▶ 1/1 彼方 — 読み: かなた') >= 0, true)
  assert.equals(index(popup_lines[1], '▶ 1/3 仮名 — 文字 / 読み: かな') >= 0, true)
  assert.equals(len(popup_lines[2]), 1)
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.pending_search_does_not_accept_or_reopen_after_immediate_enter = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<CR>" .. WAIT .. "\<F12>\<Esc>", 'xt')
  assert.equals(getline(1), '前かな')
  assert.equals(getline(2), '後')
  assert.equals(len(popup_lines[0]), 1)
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.cancelling_a_pending_search_keeps_it_closed_without_consuming_text = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<F5>" .. WAIT .. "\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後'])
  assert.equals(len(popup_lines[0]), 1)
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.disable_cancels_pending_search_before_its_timer_runs = (): void => {
  Setup()
  defer Cleanup()
  inoremap <buffer> <F11> <ScriptCmd>Caskk.Disable()<CR>
  feedkeys("aKana\<F11>" .. WAIT .. "\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後'])
  assert.equals(popup_lines[0], [])
  assert.equals(Caskk.IsEnabled(), false)
}

suite.broad_prefix_search_keeps_terminal_input_responsive_and_discards_old_results = (): void => {
  const dictionary = tempname()
  const script = tempname() .. '.vim'
  const report = tempname()
  defer delete(dictionary)
  defer delete(script)
  defer delete(report)
  defer delete(report .. '.next')
  final lines = [';; okuri-ari entries.', ';; okuri-nasi entries.']
  for number in range(20000)
    lines->add(printf('おお%05d /候補%d/', number, number))
  endfor
  lines->add('おおか /更新された候補/')
  writefile(lines, dictionary)
  writefile([
    'vim9script',
    'set rtp^=' .. escape(getcwd(), ' ,'),
    "import autoload 'caskk.vim' as C",
    "C.RegisterInputScheme({name: 'responsive', consonants: {k: 'k'}, combinations: {a: 'a', o: 'o'}})",
    'C.Config({mode_popup: false, sticky_key: ";", dictionaries: [' .. string(dictionary) .. ']})',
    "C.Enable('responsive')",
    'def Report(timer: number)',
    '  const popups = mapnew(popup_list(), (_, id) => getbufline(winbufnr(id), 1, "$"))',
    '  writefile([json_encode({text: getline(1), popups: popups, state: C.GetDictionaryLoadStatus().state})], ' .. string(report .. '.next') .. ')',
    '  rename(' .. string(report .. '.next') .. ', ' .. string(report) .. ')',
    'enddef',
    'timer_start(5, Report, {repeat: -1})',
  ], script)
  const terminal = term_start([v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-N', '-S', script],
    {hidden: true, term_rows: 12, term_cols: 60})
  try
    var state: dict<any> = {}
    for _ in range(300)
      term_wait(terminal, 10)
      if filereadable(report)
        state = json_decode(readfile(report)[0])
        if state.state ==# 'ready'
          break
        endif
      endif
    endfor
    assert.equals(get(state, 'state', ''), 'ready')
    term_sendkeys(terminal, 'i;oo')
    term_wait(terminal, 20)
    term_sendkeys(terminal, 'ka')
    for _ in range(100)
      term_wait(terminal, 10)
      state = json_decode(readfile(report)[0])
      if state.text ==# 'おおか' && stridx(string(state.popups), '更新された候補') >= 0
        break
      endif
    endfor
    assert.equals(state.text, 'おおか')
    assert.equals(stridx(string(state.popups), '更新された候補') >= 0, true)
    assert.equals(stridx(string(state.popups), '候補0') < 0, true)
    term_sendkeys(terminal, "\<CR>")
    term_wait(terminal, 100)
    state = json_decode(readfile(report)[0])
    assert.equals(state.text, '更新された候補')
    assert.equals(state.popups, [])
  finally
    job_stop(term_getjob(terminal), 'kill')
    execute 'silent! bwipeout! ' .. terminal
  endtry
}

suite.abbreviation_enter_keeps_literal_ascii_when_completions_are_visible = (): void => {
  Setup({mappings: {q: 'AbbreviationMode', "\<Space>": 'Convert', "\<CR>": 'Commit'}})
  defer Cleanup()
  feedkeys("aqapple\<F12>\<CR>\<F12>\<Esc>", 'xt')
  assert.equals(stridx(string(popup_lines[0]), '林檎') >= 0, true)
  assert.equals(captures, ['前apple後', '前apple後'])
  assert.equals(line('$'), 1)
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.abbreviation_enter_keeps_ascii_before_search_results_arrive = (): void => {
  Setup({mappings: {q: 'AbbreviationMode'}})
  defer Cleanup()
  feedkeys("aqABC123\<CR>" .. WAIT .. "\<F12>\<Esc>", 'xt')
  assert.equals(getline(1), '前ABC123後')
  assert.equals(line('$'), 1)
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.abbreviation_explicit_conversion_and_commit_still_accept_candidates = (): void => {
  Setup({mappings: {q: 'AbbreviationMode', "\<Space>": 'Convert', "\<CR>": 'Commit', "\<F10>": 'Commit'}})
  defer Cleanup()
  feedkeys("aqapple \<CR>\<F12>\<Esc>", 'xt')
  assert.equals(captures[0], '前林檎後')
  setline(1, '前後')
  cursor(1, 1)
  feedkeys("aqapple" .. WAIT .. "\<F10>\<F12>\<Esc>", 'xt')
  assert.equals(captures[1], '前林檎後')
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['apple', ''])], ['林檎'])
}
