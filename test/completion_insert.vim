vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/dictionary/lookup.vim' as dictionary_lookup
import 'caskk/dictionary.vim' as dictionary_types

final suite = themis#suite('Insert reading completion')
const assert = themis#helper('assert')
var captures: list<string> = []
var popup_lines: list<list<string>> = []
var buffer_captures: list<list<string>> = []
var selected_rows: list<number> = []
var previous = 0
var target = 0
var dictionary_path = ''
var snapshot: user_state.Snapshot = null_object
const WAIT = "\<Cmd>sleep 30m\<CR>"

def Capture()
  sleep 30m
  captures->add(getline(1))
  buffer_captures->add(getline(1, '$'))
  final lines: list<string> = []
  var selected_row = 0
  for id in popup_list()
    const buffer = winbufnr(id)
    const rows = getbufline(buffer, 1, '$')
    for row in range(1, len(rows))
      if !empty(filter(prop_list(row, {bufnr: buffer}), (_, property) => property.type ==# 'caskk_candidate_selected'))
        selected_row = row
      endif
    endfor
    lines->extend(rows)
  endfor
  popup_lines->add(lines)
  selected_rows->add(selected_row)
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
    'shrimp /シュリンプ/', 'apple /林檎/', 'application /アプリ/', 'ABC123 /英数字/'], dictionary_path)
  Caskk.RegisterInputScheme({name: 'completion-test', consonants: {k: 'k', n: 'n', t: 't'},
    combinations: {a: 'a', i: 'i'}})
  Caskk.Config(extend({dictionaries: [{path: dictionary_path, encoding: 'utf-8'}], completion_min_length: 2,
    mappings: {"\<Tab>": 'NextCompletion', "\<F5>": 'CancelCompletion', "\<Space>": 'NextCandidate'}}, options))
  inoremap <buffer> <F12> <ScriptCmd>Capture()<CR>
  captures = []
  buffer_captures = []
  selected_rows = []
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

suite.automatic_menu_is_unselected_until_show_completion = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<F12>\<Tab>\<F12>\<Tab>\<F12>\<CR>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前仮名後', '前彼方後'])
  assert.equals(selected_rows, [0, 1, 2])
  assert.equals(getline(1), '前彼方後')
}

suite.enter_with_unselected_menu_commits_reading_without_learning = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<F12>\<CR>\<Esc>", 'xt')
  assert.equals(getline(1), '前かな')
  assert.equals(getline(2), '後')
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.commit_with_unselected_menu_keeps_reading_without_learning = (): void => {
  Setup({mappings: {"\<F10>": 'Commit'}})
  defer Cleanup()
  feedkeys("aKana\<F12>\<F10>\<Esc>", 'xt')
  assert.equals(getline(1), '前かな後')
  assert.equals(line('$'), 1)
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.previous_from_first_candidate_restores_unselected_reading = (): void => {
  Setup({mappings: {"\<Tab>": 'NextCompletion', "\<F6>": 'PreviousCompletion'}})
  defer Cleanup()
  feedkeys("aKana\<F12>\<Tab>\<F12>\<F6>\<F12>\<F6>\<F12>\<Tab>\<F12>\<Up>\<F12>\<CR>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前仮名後', '前かな後', '前金物後', '前仮名後', '前かな後'])
  assert.equals(selected_rows, [0, 1, 0, 3, 1, 0])
  assert.equals(index(popup_lines[2], '仮名 — 文字') >= 0, true)
  assert.equals(getline(1), '前かな')
  assert.equals(getline(2), '後')
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.previous_candidate_does_not_move_reading_completion = (): void => {
  Setup({mappings: {a: 'PreviousCandidate'}})
  defer Cleanup()
  feedkeys("aKana\<F12>a\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前かなあ後'])
  assert.equals(selected_rows, [0, 0])
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.escape_commits_selected_completion_and_leaves_insert_mode = (): void => {
  Setup()
  defer Cleanup()
  inoremap <buffer> <Esc> <Nop>
  const original_escape = maparg('<Esc>', 'i', false, true)
  feedkeys("aKana\<Tab>" .. WAIT .. "\<F12>\<Esc>0", 'xt')
  assert.equals(captures, ['前仮名後'])
  assert.equals(col('.'), 1)
  assert.equals(maparg('<Esc>', 'i', false, true), original_escape)
  assert.equals(getline(1), '前仮名後')
  assert.equals(popup_list(), [])
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['かな', ''])], ['仮名'])
  normal! u
  assert.equals(getline(1), '前かな後')
}

suite.escape_with_unselected_completion_keeps_the_reading = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<F12>\<Esc>", 'xt')
  assert.equals(selected_rows, [0])
  assert.equals(getline(1), '前かな後')
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.menu_previews_selection_and_enter_commits_the_selected_word = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<F12>\<Tab>\<F12>\<CR>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前仮名後', '前仮名後'])
  assert.equals(selected_rows, [0, 1, 0])
  assert.equals(index(popup_lines[0], '仮名 — 文字') >= 0, true)
  assert.equals(index(popup_lines[1], '仮名 — 文字') >= 0, true)
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
  assert.equals(getline(1), '前仮名後')
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
  feedkeys("aKana" .. WAIT .. "\<Tab>\<CR>\<Esc>", 'xt')
  assert.equals(getline(1), '前仮名後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.typing_and_conversion_close_the_completion_menu = (): void => {
  Setup({candidate_select_keys: ['1']})
  defer Cleanup()
  feedkeys("aKanaki\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かなき後'])
  assert.equals(len(popup_lines[0]), 1)
  feedkeys("aKana \<F12>\<CR>\<Esc>", 'xt')
  assert.equals(index(popup_lines[1], '1 仮名 — 文字') >= 0, true)
}

suite.popup_can_be_disabled_without_disabling_completion = (): void => {
  Setup({candidate_popup: false})
  defer Cleanup()
  feedkeys("aKana\<Tab>\<F12>\<CR>\<Esc>", 'xt')
  assert.equals(captures, ['前仮名後'])
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
    'C.Config({mode_popup_time: 0, dictionaries: [' .. string({path: dictionary_path, encoding: 'utf-8'})
      .. '], mappings: {"\<Tab>": "NextCompletion"}})',
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
    assert.equals(stridx(screen, '仮名') >= 0, true)
    term_sendkeys(terminal, "\<Tab>\<CR>")
    term_wait(terminal, 100)
    assert.equals(trim(term_getline(terminal, 1)), '仮名')
  finally
    job_stop(term_getjob(terminal), 'kill')
    execute 'silent! bwipeout! ' .. terminal
  endtry
}

suite.automatic_completion_requires_no_show_completion_mapping = (): void => {
  Setup({mappings: {"\<Space>": 'NextCandidate'}})
  defer Cleanup()
  feedkeys("aKa\<F12>na\<F12>\<Down>\<CR>\<Esc>", 'xt')
  assert.equals(captures, ['前か後', '前かな後'])
  assert.equals(len(popup_lines[0]), 1)
  assert.equals(index(popup_lines[1], '仮名 — 文字') >= 0, true)
  assert.equals(getline(1), '前仮名後')
  normal! u
  assert.equals(getline(1), '前かな後')
}

suite.automatic_completion_refreshes_after_typing_and_hides_for_pending_input = (): void => {
  Setup({sticky_key: ';'})
  defer Cleanup()
  feedkeys("aKana\<F12>t\<F12>a\<F12>;\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前かなt後', '前かなた後', '前かなた後'])
  assert.equals(index(popup_lines[0], '仮名 — 文字') >= 0, true)
  assert.equals(len(popup_lines[1]), 1)
  assert.equals(index(popup_lines[2], '彼方') >= 0, true)
  assert.equals(len(popup_lines[3]), 1)
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.automatic_completion_uses_the_configured_minimum_and_returns_after_editing = (): void => {
  Setup({completion_min_length: 3, mappings: {c: 'CancelCompletion', "\<Space>": 'NextCandidate'}})
  defer Cleanup()
  feedkeys("aKana\<F12>ta\<F12>c\<BS>\<F12>ta\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前かなた後', '前かな後', '前かなた後'])
  assert.equals(len(popup_lines[0]), 1)
  assert.equals(index(popup_lines[1], '彼方') >= 0, true)
  assert.equals(len(popup_lines[2]), 1)
  assert.equals(index(popup_lines[3], '彼方') >= 0, true)
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
  assert.equals(index(popup_lines[0], '彼方') >= 0, true)
  assert.equals(index(popup_lines[1], '仮名 — 文字') >= 0, true)
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

def ReadTerminalReport(path: string): dict<any>
  var state: dict<any> = {}
  try
    state = json_decode(readfile(path)[0])
  catch /^Vim\%((\a\+)\)\=:E484:/
    # Vim removes the previous report before renaming its replacement.
  endtry
  return state
enddef

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
    'C.Config({mode_popup: false, sticky_key: ";", dictionaries: [' .. string({path: dictionary, encoding: 'utf-8'}) .. ']})',
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
      state = ReadTerminalReport(report)
      if get(state, 'state', '') ==# 'ready'
        break
      endif
    endfor
    assert.equals(get(state, 'state', ''), 'ready')
    term_sendkeys(terminal, 'i;oo')
    term_wait(terminal, 20)
    term_sendkeys(terminal, 'ka')
    for _ in range(100)
      term_wait(terminal, 10)
      state = ReadTerminalReport(report)
      if get(state, 'text', '') ==# 'おおか' && stridx(string(state.popups), '更新された候補') >= 0
        break
      endif
    endfor
    assert.equals(state.text, 'おおか')
    assert.equals(stridx(string(state.popups), '更新された候補') >= 0, true)
    assert.equals(stridx(string(state.popups), '候補0') < 0, true)
    term_sendkeys(terminal, "\<Down>\<CR>")
    for _ in range(100)
      term_wait(terminal, 10)
      state = ReadTerminalReport(report)
      if get(state, 'text', '') ==# '更新された候補' && empty(state.popups)
        break
      endif
    endfor
    assert.equals(state.text, '更新された候補')
    assert.equals(state.popups, [])
  finally
    job_stop(term_getjob(terminal), 'kill')
    execute 'silent! bwipeout! ' .. terminal
  endtry
}

suite.abbreviation_enter_commits_selected_prefix_completion = (): void => {
  Setup({mappings: {q: 'AbbreviationMode', "\<CR>": 'Commit'}})
  defer Cleanup()
  feedkeys("aqshrim" .. WAIT .. "\<Down>\<F12>\<CR>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前シュリンプ後', '前シュリンプ後'])
  assert.equals(line('$'), 1)
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['shrimp', ''])], ['シュリンプ'])
}

suite.abbreviation_enter_keeps_literal_ascii_when_completions_are_visible = (): void => {
  Setup({mappings: {q: 'AbbreviationMode', "\<Space>": 'NextCandidate', "\<CR>": 'Commit'}})
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
  Setup({mappings: {q: 'AbbreviationMode', "\<Space>": 'NextCandidate', "\<CR>": 'Commit', "\<F10>": 'Commit'}})
  defer Cleanup()
  feedkeys("aqapple" .. WAIT .. " \<CR>\<F12>\<Esc>", 'xt')
  assert.equals(captures[0], '前林檎後')
  setline(1, '前後')
  cursor(1, 1)
  feedkeys("aqapple" .. WAIT .. "\<Down>\<F10>\<F12>\<Esc>", 'xt')
  assert.equals(captures[1], '前林檎後')
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['apple', ''])], ['林檎'])
}

suite.preview_cancellation_and_typing_restore_the_original_reading = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<F12>\<Tab>\<F12>\<F5>\<F12>ki\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前仮名後', '前かな後', '前かなき後'])
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
  normal! u
  assert.equals(getline(1), '前後')
  execute "normal! \<C-r>"
  assert.equals(getline(1), '前かなき後')
}

suite.leaving_preview_does_not_commit_or_learn_the_focused_word = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana" .. WAIT .. "\<Tab>\<Left>\<Esc>", 'xt')
  assert.equals(getline(1), '前かな後')
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.multiline_preview_cancellation_restores_surrounding_buffer_text = (): void => {
  Setup()
  defer Cleanup()
  const query = dictionary_lookup.CreateQuery('かな', '')
  user_runtime.Get().AddEntry(query, dictionary_types.Candidate.new("複\n数行", []))
  user_runtime.Get().Pin(query, "複\n数行")
  feedkeys("aKana" .. WAIT .. "\<Tab>\<F12>\<F5>\<F12>\<Esc>", 'xt')
  assert.equals(buffer_captures, [['前複', '数行後'], ['前かな後']])
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}

suite.typing_after_a_selected_completion_commits_then_starts_new_input = (): void => {
  Setup()
  defer Cleanup()
  feedkeys("aKana\<F12>\<Tab>ki\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前仮名き後'])
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['かな', ''])], ['仮名'])
  normal! u
  assert.equals(getline(1), '前仮名後')
}

suite.space_after_a_selected_completion_commits_and_inserts_a_space = (): void => {
  Setup({candidate_select_keys: ['1'], mode_popup: false})
  defer Cleanup()
  feedkeys("aKana" .. WAIT .. "\<Tab>\<F12>\<Space>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前仮名後', '前仮名 後'])
  assert.equals(popup_lines[1], [])
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['かな', ''])], ['仮名'])
}

suite.adjective_label_stays_in_popup_while_commit_and_undo_keep_plain_text = (): void => {
  const source = tempname()
  defer delete(source)
  writefile(['かな /仮名;@adj/'], source)
  Setup({dictionaries: [{path: source, encoding: 'utf-8'}], completion_min_length: 20, mappings: {"\<F10>": "Commit"}})
  defer Cleanup()
  feedkeys("aKanaI\<F12>\<F10>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前仮名い後', '前仮名い後'])
  assert.equals(stridx(string(popup_lines[0]), '仮名い[形]') >= 0, true)
  assert.equals(empty(user_runtime.Get().GetSnapshot().mru), false)
  normal! u
  assert.equals(getline(1), '前かない後')
}

suite.verb_label_stays_in_popup_while_commit_and_undo_keep_plain_text = (): void => {
  const source = tempname()
  defer delete(source)
  writefile([';; okuri-ari entries.', ';; okuri-nasi entries.', 'かな /仮名;説明;@verb-5-k @unknown/'], source)
  Setup({dictionaries: [{path: source, encoding: 'utf-8'}], completion_min_length: 20, mappings: {"\<F10>": 'Commit'}})
  defer Cleanup()
  feedkeys("aKanaKi\<F12>\<F10>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前仮名き後', '前仮名き後'])
  assert.equals(stridx(string(popup_lines[0]), '仮名き[カ五] — 説明;@unknown') >= 0, true)
  assert.equals(stridx(string(popup_lines[0]), '@verb-5-k'), -1)
  assert.equals(empty(user_runtime.Get().GetSnapshot().mru), false)
  normal! u
  assert.equals(getline(1), '前かなき後')
}

suite.verb_only_stem_does_not_open_automatic_completion = (): void => {
  const source = tempname()
  defer delete(source)
  writefile([';; okuri-ari entries.', ';; okuri-nasi entries.', 'かな /仮名;@verb-5-k/'], source)
  Setup({dictionaries: [{path: source, encoding: 'utf-8'}]})
  defer Cleanup()
  feedkeys("aKana\<F12>Ki\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前かな後', '前仮名き後'])
  assert.equals(stridx(string(popup_lines[0]), '仮名') < 0, true)
  assert.equals(selected_rows[0], 0)
}

suite.zero_okuri_imperative_converts_with_a_verb_marker = (): void => {
  const source = tempname()
  defer delete(source)
  writefile([';; okuri-ari entries.', ';; okuri-nasi entries.',
    'くれ /呉れ;@verb-1-kureru/'], source)
  Setup({dictionaries: [{path: source, encoding: 'utf-8'}], mappings: {"\<Space>": 'NextCandidate', "\<F10>": 'Commit'}})
  defer Cleanup()
  Caskk.Disable()
  Caskk.RegisterInputScheme({name: 'bare-imperative', consonants: {}, combinations: {}, specials: {x: 'くれ'}})
  Caskk.Enable('bare-imperative')
  feedkeys("aX \<F12>\<F10>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前呉れ後', '前呉れ後'])
  assert.equals(index(popup_lines[0], '呉れ[下一(呉)]') >= 0, true)
}

suite.typed_adjective_suffix_preview_cancel_commit_and_undo = (): void => {
  const source = tempname()
  defer delete(source)
  writefile(['おいし /美味し;@adj/'], source)
  Setup({dictionaries: [{path: source, encoding: 'utf-8'}]})
  defer Cleanup()
  Caskk.Disable()
  Caskk.RegisterInputScheme({name: 'suffix-completion', consonants: {}, combinations: {},
    specials: {x: 'おいしくなりました'}})
  Caskk.Enable('suffix-completion')
  feedkeys("aX\<F12>\<Tab>\<F12>\<F5>\<F12>\<Tab>" .. WAIT .. "\<CR>\<Esc>", 'xt')
  assert.equals(captures, ['前おいしくなりました後', '前美味しくなりました後', '前おいしくなりました後'])
  assert.equals(getline(1), '前美味しくなりました後')
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['おいし', ''])], ['美味し'])
  normal! u
  assert.equals(getline(1), '前おいしくなりました後')
}

suite.sokuon_and_suffix_special_convert_commit_and_undo_in_vim = (): void => {
  const source = tempname()
  defer delete(source)
  writefile(['かt /勝/'], source)
  Setup({dictionaries: [{path: source, encoding: 'utf-8'}], completion_min_length: 20, mappings: {"\<F10>": 'Commit'}})
  defer Cleanup()
  Caskk.Disable()
  Caskk.RegisterInputScheme({name: 'sokuon-special', consonants: {t: 't', tt: 'Tt'},
    combinations: {a: 'a'}, specials: {x: 'か', ta: 'だ'}})
  Caskk.Enable('sokuon-special')
  feedkeys("aXTta\<F12>\<F10>\<Esc>", 'xt')
  assert.equals(captures, ['前勝っだ後'])
  assert.equals(getline(1), '前勝っだ後')
  normal! u
  assert.equals(getline(1), '前かっだ後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.affix_readings_stay_out_of_automatic_candidate_popup = (): void => {
  Setup()
  defer Cleanup()
  writefile(['か> /御/'], dictionary_path)
  Caskk.Disable()
  Caskk.Config({dictionaries: [{path: dictionary_path, encoding: 'utf-8'}], sticky_key: ';', affix_key: '1',
    mode_popup: false, mappings: {"\<Space>": 'NextCandidate'}})
  Caskk.Enable('completion-test')
  feedkeys("a;ka1\<F12>\<Space>\<F12>\<Esc>", 'xt')
  assert.equals(captures, ['前か>後', '前御後'])
  assert.equals(popup_lines[0], [])
  assert.equals(empty(popup_lines[1]), false)
}
