vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
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
var captured_enabled: bool = true
var dictionary_directory: string = ''

def g:CaskkTestInlineCapture()
  const windows = popup_list()
  popup_lines = []
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
      popup_screen_line = position.line
      popup_buffer = winbufnr(window)
      popup_options = popup_getoptions(window)
      if !empty(prop_type_get('caskk_preedit', {bufnr: popup_buffer}))
        registration_highlights = prop_list(2, {bufnr: popup_buffer, types: ['caskk_preedit']})
      endif
    else
      visible_mode_labels += lines
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

def Setup(prefill: bool = false, with_candidates: bool = false): list<number>
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
    mappings: {s: 'Convert', n: 'NextCandidate', "\<F6>": 'OpenRegistration'}}
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
    '  1/2 蚊', '▶ 2/2 科'])
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
    candidates->add((index == 1 ? '▶ ' : '  ') .. index .. '/35 候補' .. index)
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
  assert.equals(popup_lines[2], '▶ 1/1 行く')
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
