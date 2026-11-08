vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/dictionary/lookup.vim' as lookup
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/presentation/registration_inline.vim' as RegistrationInline

final suite = themis#suite('in-buffer dictionary registration')
const assert = themis#helper('assert')
var previous_state: user_state.Snapshot = null_object
var popup_lines: list<string> = []
var popup_observations: list<list<string>> = []
var source_undo_states: list<list<number>> = []
var popup_screen_line: number = 0
var popup_buffer: number = -1
var popup_options: dict<any> = {}
var registration_highlights: list<dict<any>> = []
var visible_mode_labels: list<string> = []
var mode_screen_line: number = 0
var mode_screen_col: number = 0
var registration_position: dict<number> = {}
var selected_candidate_rows: list<number> = []
var captured_enabled: bool = true
var dictionary_directory: string = ''

def g:CaskkTestInlineCapture()
  const windows = popup_list()
  popup_lines = []
  selected_candidate_rows = []
  registration_highlights = []
  visible_mode_labels = []
  popup_screen_line = 0
  popup_buffer = -1
  popup_options = {}
  captured_enabled = Caskk.IsEnabled()
  for window in windows
    const lines = getbufline(winbufnr(window), 1, '$')
    if !empty(lines) && lines[0] =~# '^辞書登録'
      popup_lines = lines
      const position = popup_getpos(window)
      registration_position = position
      popup_screen_line = position.line
      popup_buffer = winbufnr(window)
      popup_options = popup_getoptions(window)
      for row in range(1, len(lines))
        if !empty(prop_list(row, {bufnr: popup_buffer, types: ['caskk_candidate_selected']}))
          selected_candidate_rows->add(row)
        endif
      endfor
      if !empty(prop_type_get('caskk_preedit', {bufnr: popup_buffer}))
        registration_highlights = prop_list(2, {bufnr: popup_buffer, types: ['caskk_preedit']})
      endif
    else
      visible_mode_labels += lines
      mode_screen_line = popup_getpos(window).line
      mode_screen_col = popup_getpos(window).col
    endif
  endfor
  popup_observations->add(copy(popup_lines))
  source_undo_states->add([b:changedtick, undotree().seq_cur])
enddef

def g:CaskkTestInlineDisable()
  Caskk.Disable()
enddef

def g:CaskkTestInlineReloadConfig()
  Caskk.Config({})
enddef

def Setup(prefill: bool = false, with_candidates: bool = false, extra_mappings: dict<string> = {}): list<number>
  previous_state = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setlocal bufhidden=hide
  setline(1, '前後')
  cursor(1, 1)
  var options: dict<any> = {registration_auto: false, registration_inline: true,
    registration_prefill: prefill,
    highlight: {preedit: {term: 'underline', cterm: 'underline', gui: 'underline'}},
    mode_popup: true, mode_popup_time: 0,
    mappings: extend({s: 'Convert', n: 'NextCandidate', "\<F6>": 'OpenRegistration'}, extra_mappings)}
  if with_candidates
    dictionary_directory = tempname()
    mkdir(dictionary_directory)
    writefile(['か /蚊/科/', 'かk /行/'], dictionary_directory .. '/system')
    options.dictionaries = [dictionary_directory .. '/system']
  endif
  Caskk.Config(options)
  Caskk.RegisterInputScheme({name: 'registration-inline', consonants: {k: 'k'},
    combinations: {a: 'a*', u: 'u'}, specials: {z: '漢字'}})
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
    if dictionary_directory !=# ''
      delete(dictionary_directory, 'rf')
      dictionary_directory = ''
    endif
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

suite.inline_popup_shows_the_registration_text_and_edit_position = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>z\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢字│'])
  assert.equals(getline(1), '前か後')
  assert.equals(bufnr('%'), context[1])
}

suite.inline_registration_highlights_ime_composition_and_shows_its_mode_marker = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>KaKa\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: かか│'])
  assert.equals(len(registration_highlights), 1)
  assert.equals(registration_highlights[0].length, strlen('かか'))
  assert.equals(visible_mode_labels, ['▽あ'])
  assert.equals(getline(1), '前か後')
}

suite.inline_popup_moves_below_the_cursor_when_the_top_edge_has_no_room = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_screen_line > 1, true)
}

suite.inline_popup_requests_above_cursor_placement_with_automatic_inversion = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_options.pos, 'botleft')
  assert.equals(popup_options.posinvert, true)
  assert.equals(popup_options.line, -1)
}

suite.editing_the_popup_does_not_change_the_source_buffer_or_its_undo_history = (): void => {
  const context = Setup()
  defer Cleanup(context)
  source_undo_states = []
  feedkeys("aKas\<F6>\<Cmd>call CaskkTestInlineCapture()\<CR>z\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(source_undo_states[1], source_undo_states[0])
  assert.equals(getline(1), '前か後')
}

suite.inline_popup_moves_and_deletes_committed_registration_text = (): void => {
  const context = Setup()
  defer Cleanup(context)
  popup_observations = []
  feedkeys("aKas\<F6>z\<Left>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Del>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_observations[0], ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢│字'])
  assert.equals(popup_observations[1], ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢│'])
  assert.equals(getline(1), '前か後')
  assert.equals(popup_list(), [])
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
}

suite.inline_popup_backspace_and_input_edit_at_the_logical_caret = (): void => {
  const context = Setup()
  defer Cleanup(context)
  popup_observations = []
  feedkeys("aKas\<F6>z\<Left>z\<Cmd>call CaskkTestInlineCapture()\<CR>\<BS>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_observations[0], ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢漢字│字'])
  assert.equals(popup_observations[1], ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢漢│字'])
  assert.equals(getline(1), '前か後')
}

suite.unsupported_native_motion_is_ignored_while_inline_registration_is_open = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>z\<Up>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢字│'])
  assert.equals(getline(1), '前か後')
}

suite.unsupported_insert_control_does_not_edit_the_source_buffer_and_is_restored = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>z\<C-W>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢字│'])
  assert.equals(getline(1), '前か後')
  assert.equals(maparg("\<C-W>", 'i'), '')
}

suite.inline_registration_prefill_starts_as_editable_reading = (): void => {
  const context = Setup(true)
  defer Cleanup(context)
  feedkeys("aKas\<F6>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: か│'])
  assert.equals(getline(1), '前か後')
}

suite.inline_registration_rejects_empty_text_without_closing_the_popup = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>\<CR>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: │', '登録語を入力してください'])
  assert.equals(getline(1), '前か後')
}

suite.inline_candidate_selection_keeps_the_registration_draft_visible = (): void => {
  const context = Setup(true, true)
  defer Cleanup(context)
  feedkeys("aKasnn\<F6>sn\<Cmd>call CaskkTestInlineCapture()\<CR>\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 科│',
    '1/2 蚊', '2/2 科'])
  assert.equals(selected_candidate_rows, [4])
  assert.equals(index(visible_mode_labels, '▼あ') >= 0, true)
  assert.equals(getline(1), '前科後')
  assert.equals(popup_list() == [], true)
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
}

suite.registration_popup_keeps_its_screen_position_when_candidate_list_expands = (): void => {
  const context = Setup()
  defer Cleanup(context)
  append(0, repeat([''], 7))
  cursor(8, 1)
  const inline_popup = RegistrationInline.View.new()
  const old_popups = popup_list()
  inline_popup.Show(['辞書登録: く', '登録語: │'])
  const popup = filter(popup_list(), (_, id) => index(old_popups, id) < 0)[0]
  const initial = popup_getpos(popup)
  var candidates = ['辞書登録: く', '登録語: か│']
  for index in range(1, 35)
    candidates->add(index .. '/35 候補' .. index)
  endfor
  inline_popup.Show(candidates)
  const updated = popup_getpos(popup)
  const options = popup_getoptions(popup)
  assert.equals([updated.line, updated.col], [initial.line, initial.col])
  assert.equals(options.line, initial.line)
  assert.equals(options.col, initial.col)
  assert.equals(options.pos, 'topleft')
  assert.equals(options.posinvert, false)
  inline_popup.Close()
}

suite.escape_commits_the_selected_registration_candidate_without_cancelling_registration = (): void => {
  const context = Setup(true, true)
  defer Cleanup(context)
  feedkeys("aKasnn\<F6>sn\<Esc>\<Cmd>call CaskkTestInlineCapture()\<CR>\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 科│'])
  assert.equals(getline(1), '前科後')
}

suite.inline_registration_converts_a_reading_with_okuri = (): void => {
  const context = Setup(false, true)
  defer Cleanup(context)
  feedkeys("aKasnn\<F6>KaKu\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>\<Esc>", 'xt')
  assert.equals(popup_lines[0 : 1], ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 行く│'])
  assert.equals(len(popup_lines) > 2, true)
  assert.equals(popup_lines[2], '1/1 行く')
}

suite.disabling_caskk_keeps_inline_registration_open_for_direct_text_entry = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>z\<Cmd>call CaskkTestInlineDisable()\<CR>x\<Cmd>call CaskkTestInlineCapture()\<CR>\<CR>\<Esc>", 'xt')
  assert.equals(Caskk.IsEnabled(), false)
  assert.equals(captured_enabled, false)
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢字x│'])
  assert.equals(getline(1), '前漢字x後')
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
}

suite.reloading_configuration_still_discards_inline_registration_state = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>z\<Cmd>call CaskkTestInlineReloadConfig()\<CR>", 'xt')
  assert.equals(popup_list(), [])
  assert.equals(Caskk.IsEnabled(), false)
}

suite.ctrl_c_closes_inline_registration_and_finalizes_only_the_source_reading = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>z\<C-C>", 'xt')
  assert.equals(popup_list(), [])
  assert.equals(getline(1), '前か後')
  assert.equals(Caskk.GetRegistrationRequest() is null_object, true)
}

suite.leaving_the_source_buffer_closes_the_inline_popup_and_keeps_its_reading = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const target = bufadd(tempname())
  bufload(target)
  feedkeys("aKas\<F6>z\<Cmd>execute 'buffer " .. target .. "'\<CR>", 'xt')
  assert.equals(bufnr('%'), target)
  assert.equals(popup_list(), [])
  assert.equals(getbufline(context[1], 1), ['前か後'])
  execute 'noautocmd keepalt hide buffer ' .. context[1]
  execute 'silent! bwipeout! ' .. target
}

suite.wiping_the_source_buffer_closes_and_removes_the_inline_popup = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>z\<Cmd>call CaskkTestInlineCapture()\<CR>\<Cmd>execute 'bwipeout! "
    .. context[1] .. "'\<CR>", 'xt')
  assert.equals(bufexists(context[1]), 0)
  assert.equals(popup_list(), [])
  assert.equals(bufexists(popup_buffer), 0)
}

suite.closing_the_source_window_closes_inline_registration_and_keeps_the_reading = (): void => {
  const context = Setup()
  defer Cleanup(context)
  execute 'vsplit'
  win_gotoid(context[2])
  feedkeys("aKas\<F6>z\<Cmd>close!\<CR>", 'xt')
  assert.equals(win_id2win(context[2]), 0)
  assert.equals(popup_list(), [])
  assert.equals(bufnr('%'), context[1])
  assert.equals(getline(1), '前か後')
}

suite.inline_mode_popup_is_below_the_registration_popup = (): void => {
  const context = Setup()
  defer Cleanup(context)
  append(0, repeat([''], 10))
  cursor(11, 1)
  feedkeys("aKas\<F6>z\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>\<Esc>", 'xt')
  assert.equals(visible_mode_labels, ['あ'])
  assert.equals(mode_screen_line, registration_position.line + registration_position.height)
  assert.equals(mode_screen_col, registration_position.col)
}

suite.terminal_paste_goes_to_the_registration_draft_without_editing_the_source = (): void => {
  const script = tempname() .. '.vim'
  const report = tempname()
  defer delete(script)
  defer delete(report)
  writefile([
    'vim9script',
    'set rtp^=' .. escape(getcwd(), ' ,'),
    "import autoload 'caskk.vim' as C",
    "C.RegisterInputScheme({name: 'paste', consonants: {k: 'k'}, combinations: {a: 'a'}, specials: {z: '漢字'}})",
    'C.Config({registration_inline: true, registration_auto: false, registration_prefill: false, mode_popup: false,',
    '  mappings: {s: "Convert", "\<F6>": "OpenRegistration"}})',
    "setline(1, '前後')",
    'cursor(1, 1)',
    "C.Enable('paste')",
    'def Capture(timer: number)',
    "  const popups = mapnew(popup_list(), (_, id) => getbufline(winbufnr(id), 1, '$'))",
    '  writefile([json_encode({text: getline(1), tick: b:changedtick, undo: undotree().seq_cur, popups: popups})], ' .. string(report) .. ', "a")',
    'enddef',
    'timer_start(10, Capture, {repeat: -1})',
    'writefile(["ready"], ' .. string(report) .. ')',
  ], script)
  const terminal = term_start([v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-N', '-S', script],
    {hidden: true, term_rows: 16, term_cols: 70})
  try
    for _ in range(100)
      term_wait(terminal, 10)
      if filereadable(report)
        break
      endif
    endfor
    term_sendkeys(terminal, "aKas\<F6>")
    term_wait(terminal, 150)
    const before = json_decode(readfile(report)[-1])
    term_sendkeys(terminal, "\e[200~漢字Ka;sn\e[201~")
    term_wait(terminal, 150)
    const pasted = json_decode(readfile(report)[-1])
    assert.equals(pasted.text, before.text)
    assert.equals([pasted.tick, pasted.undo], [before.tick, before.undo])
    assert.equals(pasted.popups, [['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢字Ka;sn│']])
    term_sendkeys(terminal, "\<CR>")
    term_wait(terminal, 150)
    assert.equals(json_decode(readfile(report)[-1]).text, '前漢字Ka;sn後')
    term_sendkeys(terminal, "\e[200~外\e[201~")
    term_wait(terminal, 150)
    assert.equals(json_decode(readfile(report)[-1]).text, '前漢字Ka;sn外後')
  finally
    job_stop(term_getjob(terminal), 'kill')
    execute 'silent! bwipeout! ' .. terminal
  endtry
}

suite.paste_inserts_literal_text_at_the_registration_caret = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>z\<Left>\<PasteStart>Ka;sn\<PasteEnd>\<Cmd>call CaskkTestInlineCapture()\<CR>\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: 漢Ka;sn│字'])
  assert.equals(getline(1), '前漢Ka;sn字後')
}

suite.paste_preserves_prefill_and_can_be_cancelled_after_disabling_ime = (): void => {
  const context = Setup(true)
  defer Cleanup(context)
  inoremap <buffer> <PasteStart> 元のペースト
  const old_paste_mapping = maparg('<PasteStart>', 'i', false, true)
  feedkeys("aKas\<F6>\<Cmd>call CaskkTestInlineDisable()\<CR>\<PasteStart>貼付Ka\<PasteEnd>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: か  [Enter:登録 Esc:取消]', '登録語: か貼付Ka│'])
  assert.equals(getline(1), '前か後')
  assert.equals(maparg('<PasteStart>', 'i', false, true), old_paste_mapping)
}

suite.backspace_cancels_inline_candidate_without_committing_it_to_the_draft = (): void => {
  const context = Setup(false, true)
  defer Cleanup(context)
  feedkeys("aKus\<F6>Kas\<BS>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>\<Esc>", 'xt')
  assert.equals(popup_lines, ['辞書登録: く  [Enter:登録 Esc:取消]', '登録語: │'])
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
  assert.equals(getline(1), '前く後')
}

suite.explicit_backspace_mapping_deletes_an_inline_user_entry = (): void => {
  const context = Setup(false, true, {"\<BS>": 'DeleteUserEntry'})
  defer Cleanup(context)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  feedkeys("aKus\<F6>Kasnn\<BS>\<Cmd>call CaskkTestInlineCapture()\<CR>y\<Esc>\<Esc>", 'xt')
  assert.equals(popup_lines[-1], 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消')
  assert.equals(user_runtime.Get().HasEntryForLookup(lookup.CreateQuery('か', ''), '登録のみ'), false)
}

suite.unavailable_inline_backspace_actions_cancel_conversion_without_learning = (): void => {
  for action in ['DeleteUserEntry', 'KatakanaMode', 'OpenRegistration', 'ShowCompletion', 'CancelCompletion']
    const context = Setup(false, true, {"\<BS>": action})
    try
      feedkeys("aKus\<F6>Kas\<BS>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>\<Esc>", 'xt')
      assert.equals(popup_lines, ['辞書登録: く  [Enter:登録 Esc:取消]', '登録語: │'], action)
      assert.equals(user_runtime.Get().GetSnapshot().mru, {}, action)
      assert.equals(getline(1), '前く後', action)
    finally
      Cleanup(context)
    endtry
  endfor
}

suite.available_inline_backspace_action_keeps_candidate_navigation = (): void => {
  const context = Setup(false, true, {"\<BS>": 'NextCandidate'})
  defer Cleanup(context)
  feedkeys("aKus\<F6>Kas\<BS>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>\<Esc>", 'xt')
  assert.equals(popup_lines[1], '登録語: 科│')
}


suite.empty_preedit_backspace_preserves_the_registration_draft = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("aKas\<F6>zKa\<BS>\<BS>\<Cmd>call CaskkTestInlineCapture()\<CR>\<Esc>", 'xt')
  assert.equals(popup_lines[1], '登録語: 漢字│')
}
