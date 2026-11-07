vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime

final suite = themis#suite('command-line input')
const assert = themis#helper('assert')
var captured = ''
var enabled = false
var snapshot: user_state.Snapshot = null_object

def Enable()
  Caskk.Enable('commandline')
enddef

def Capture()
  captured = getcmdline()
  enabled = Caskk.IsEnabled()
enddef

def Setup()
  snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  Caskk.Config({sticky_key: ';', mappings: {"\<Space>": 'Convert', "\<C-N>": 'NextCandidate',
    "\<C-P>": 'PreviousCandidate', "\<F4>": 'KatakanaMode'}})
  Caskk.RegisterInputScheme({name: 'commandline', consonants: {k: 'k'}, combinations: {a: 'a'}})
  cnoremap <F2> <ScriptCmd>Enable()<CR>
  cnoremap <F3> <ScriptCmd>Capture()<CR>
  captured = ''
enddef

def Cleanup()
  Caskk.Disable()
  Caskk.Config({})
  cunmap <F2>
  cunmap <F3>
  user_runtime.Get().Restore(snapshot)
enddef

suite.three_commandline_types_enable_independently_and_cleanup = (): void => {
  Setup()
  defer Cleanup()
  for kind in [':', '/', '?']
    feedkeys(kind .. "\<F2>ka\<F3>\<C-C>", 'xt')
    assert.equals(captured, 'か')
    assert.equals(enabled, true)
    assert.equals(Caskk.IsEnabled(), false)
    assert.equals(maparg('k', 'c'), '')
  endfor
}

suite.enter_commits_preedit_before_executing = (): void => {
  Setup()
  defer Cleanup()
  feedkeys(":\<F2>Ka\<CR>\<F3>\<C-C>", 'xt')
  assert.equals(captured, 'か')
  assert.equals(enabled, true)
}

suite.native_motion_closes_the_range_and_preserves_surrounding_text = (): void => {
  Setup()
  defer Cleanup()
  feedkeys(":前後\<Left>\<F2>Ka\<Left>ka\<F3>\<C-C>", 'xt')
  assert.equals(captured, '前かか後')
}

def Dictionary(): string
  const path = tempname()
  writefile(['か /蚊/家/', 'かk /書/'], path)
  Caskk.Config({dictionaries: [path], sticky_key: ';', mappings: {"\<Space>": 'Convert',
    "\<C-N>": 'NextCandidate', "\<C-P>": 'PreviousCandidate', "\<F4>": 'KatakanaMode'}})
  return path
enddef

def ExternalChange()
  setcmdline('外部', 1)
enddef

suite.conversion_navigation_cancel_exhaustion_and_learning = (): void => {
  Setup()
  defer Cleanup()
  const path = Dictionary()
  defer delete(path)
  feedkeys(":\<F2>Ka \<C-N>\<F3>\<C-P>\<C-P>\<F3>\<C-C>", 'xt')
  assert.equals(captured, 'か')
  feedkeys(":\<F2>Ka  \<CR>\<F3>\<C-C>", 'xt')
  assert.equals(captured, '家')
  feedkeys(":\<F2>Ka \<F3>\<C-C>", 'xt')
  assert.equals(captured, '家')
  feedkeys(":\<F2>Ka   \<F3>\<C-C>", 'xt')
  assert.equals(captured, 'か')
}

suite.okuri_sticky_modes_missing_dictionary_and_backspace = (): void => {
  Setup()
  defer Cleanup()
  const path = Dictionary()
  defer delete(path)
  feedkeys(":\<F2>;kaKa\<F3>\<C-C>", 'xt')
  assert.equals(captured, '書か')
  feedkeys(":\<F2>Ka \<BS>ka\<F3>\<C-C>", 'xt')
  assert.equals(captured, 'か')
  feedkeys(":\<F2>Kaka \<BS>ka\<F3>\<C-C>", 'xt')
  assert.equals(captured, 'かか')
  feedkeys(":\<F2>\<F4>ka\<F4>ka\<F3>\<C-C>", 'xt')
  assert.equals(captured, 'カか')
}

suite.external_changes_never_reuse_the_old_range = (): void => {
  Setup()
  defer Cleanup()
  cnoremap <F5> <ScriptCmd>ExternalChange()<CR>
  try
    feedkeys(":\<F2>Ka\<F5>ka\<F3>\<C-C>", 'xt')
    assert.equals(captured, 'か外部')
  finally
    cunmap <F5>
  endtry
}

suite.nested_input_is_native_and_outer_session_resumes = (): void => {
  Setup()
  defer Cleanup()
  feedkeys(":\<F2>Ka\<C-R>='ka'\<CR>ka\<F3>\<C-C>", 'xt')
  assert.equals(captured, 'かkaか')
}

suite.native_register_input_and_history_preserve_the_committed_reading = (): void => {
  Setup()
  defer Cleanup()
  const old_register = @z
  @z = '登録'
  try
    feedkeys(":\<F2>Ka\<C-R>zka\<F3>\<C-C>", 'xt')
    assert.equals(captured, 'か登録か')
    histadd(':', 'か履歴')
    feedkeys(":\<F2>Ka\<Up>\<F3>\<C-C>", 'xt')
    assert.equals(captured, 'か履歴')
  finally
    @z = old_register
  endtry
}

suite.commandline_enable_does_not_change_insert_enable = (): void => {
  Setup()
  defer Cleanup()
  Caskk.Enable('commandline')
  feedkeys(":\<F2>ka\<F3>\<C-C>", 'xt')
  assert.equals(captured, 'か')
  assert.equals(Caskk.IsEnabled(), true)
}

suite.buffer_local_command_mappings_are_restored = (): void => {
  Setup()
  defer Cleanup()
  cnoremap <buffer> k 旧
  const before = maparg('k', 'c', false, true)
  try
    feedkeys(":\<F2>ka\<F3>\<C-C>", 'xt')
    assert.equals(captured, 'か')
    assert.equals(maparg('k', 'c', false, true), before)
  finally
    cunmap <buffer> k
  endtry
}

var popup_text: list<string> = []
var popup_position: dict<number> = {}

def CapturePopup()
  redraw
  popup_text = []
  for id in popup_list()
    popup_text->extend(getbufline(winbufnr(id), 1, '$'))
    const pos = popup_getpos(id)
    popup_position = {line: pos.line, col: pos.col, width: pos.width, height: pos.height}
  endfor
enddef

suite.popup_labels_markers_position_and_cleanup = (): void => {
  Setup()
  defer Cleanup()
  Caskk.Config({mode_popup_time: 0, mode_popup_labels: {hiragana: 'かな'},
    mode_popup_markers: {modified: '読', candidate: '選'}})
  cnoremap <F6> <ScriptCmd>CapturePopup()<CR>
  try
    feedkeys(":\<F2>Ka\<F6>\<C-C>", 'xt')
    assert.equals(popup_text, ['読かな'])
    assert.equals(popup_position.col, 4)
    assert.equals(popup_position.line <= &lines - &cmdheight, true)
    assert.equals(popup_list(), [])
    const prefix = repeat('あ', &columns)
    feedkeys(':' .. prefix .. "\<F2>ka\<Left>\<F6>\<C-C>", 'xt')
    assert.equals(popup_position.col >= 1, true)
    assert.equals(popup_position.col + popup_position.width - 1 <= &columns, true)
    assert.equals(popup_position.line + popup_position.height - 1 < &lines, true)
    Caskk.Config({mode_popup: false})
    feedkeys(":\<F2>Ka\<F6>\<C-C>", 'xt')
    assert.equals(popup_text, [])
  finally
    cunmap <F6>
  endtry
}

suite.second_enter_executes_the_command = (): void => {
  Setup()
  defer Cleanup()
  g:caskk_commandline_executed = ''
  feedkeys(":g:caskk_commandline_executed = '\<F2>Ka\<CR>'\<CR>", 'xt')
  assert.equals(g:caskk_commandline_executed, 'か')
  assert.equals(Caskk.IsEnabled(), false)
}

suite.abbreviation_and_output_mode_conversion = (): void => {
  Setup()
  defer Cleanup()
  Caskk.Config({mappings: {"\<F7>": 'AbbreviationMode', "\<F8>": 'FullwidthAlphanumericMode',
    "\<F4>": 'KatakanaMode'}})
  feedkeys(":\<F2>\<F7>abc\<F8>\<F3>\<C-C>", 'xt')
  assert.equals(captured, 'ａｂｃ')
  feedkeys(":\<F2>Ka\<F4>\<F3>\<C-C>", 'xt')
  assert.equals(captured, 'カ')
}

def CompleteReading(lead: string, line: string, cursor: number): list<string>
  return ['か完了']
enddef

suite.native_completion_commits_and_closes_preedit = (): void => {
  Setup()
  defer Cleanup()
  const old_wildmode = &wildmode
  set wildmode=full
  command -nargs=* -complete=customlist,CompleteReading CaskkCommandlineTest echo <q-args>
  try
    feedkeys(":CaskkCommandlineTest \<F2>Ka\<Tab>\<F3>\<C-C>", 'xt')
    assert.equals(captured, 'CaskkCommandlineTest か完了')
  finally
    &wildmode = old_wildmode
    delcommand CaskkCommandlineTest
  endtry
}

suite.input_prompt_is_native_in_an_interactive_vim = (): void => {
  const script = tempname() .. '.vim'
  const output = tempname()
  defer delete(script)
  defer delete(output)
  writefile([
    'vim9script',
    '&cedit = "\<C-F>"',
    'set rtp^=' .. escape(getcwd(), ' ,'),
    "import autoload 'caskk.vim' as C",
    "C.Config({})",
    "C.RegisterInputScheme({name: 'nested', consonants: {k: 'k'}, combinations: {a: 'a'}})",
    'def Enable()', "  C.Enable('nested')", 'enddef',
    'var answer = ""',
    'def Nested()', "  answer = input('nested: ')", 'enddef',
    'def Capture()',
    '  writefile([answer, getcmdline()], ' .. string(output) .. ')', 'enddef',
    'cnoremap <F2> <ScriptCmd>Enable()<CR>',
    'cnoremap <F3> <ScriptCmd>Capture()<CR>',
    'cnoremap <F5> <ScriptCmd>Nested()<CR>',
    'feedkeys(":\<F2>Ka\<F5>ka\<CR>ka\<F3>\<C-C>", "xt")',
    'def g:CaskkTestInteractiveCmdwin()',
    "  C.Enable('nested')",
    '  writefile([string(C.IsEnabled()), getcmdwintype(), getline(".")], ' .. string(output) .. ', "a")',
    'enddef',
    'nnoremap <F9> <Cmd>call CaskkTestInteractiveCmdwin()<CR>',
    'writefile(["ready"], ' .. string(output) .. ', "a")',
  ], script)
  const terminal = term_start([v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-N', '-S', script],
    {hidden: true})
  try
    for _ in range(100)
      term_wait(terminal, 10)
      if filereadable(output) && len(readfile(output)) == 3
        break
      endif
    endfor
    term_sendkeys(terminal, ":\<F2>Ka\<C-F>")
    term_wait(terminal, 100)
    term_sendkeys(terminal, "\<F9>")
    for _ in range(100)
      term_wait(terminal, 10)
      if filereadable(output) && len(readfile(output)) == 6
        break
      endif
    endfor
    term_sendkeys(terminal, ":q!\<CR>\<C-C>:qa!\<CR>")
    for _ in range(100)
      term_wait(terminal, 10)
      if job_status(term_getjob(terminal)) != 'run'
        break
      endif
    endfor
    assert.equals(filereadable(output), 1)
    assert.equals(readfile(output), ['ka', 'かか', 'ready', 'false', ':', 'か'])
  finally
    if job_status(term_getjob(terminal)) == 'run'
      job_stop(term_getjob(terminal), 'kill')
    endif
    execute 'silent! bwipeout! ' .. terminal
  endtry
}

suite.escape_aborts_without_executing = (): void => {
  Setup()
  defer Cleanup()
  g:caskk_commandline_executed = ''
  feedkeys(":g:caskk_commandline_executed = '\<F2>Ka\<CR>'\<Esc>", 'xt')
  assert.equals(g:caskk_commandline_executed, '')
  assert.equals(Caskk.IsEnabled(), false)
  assert.equals(popup_list(), [])
}

suite.popup_candidate_marker_and_mode_follow_the_session = (): void => {
  Setup()
  defer Cleanup()
  const path = Dictionary()
  defer delete(path)
  cnoremap <F6> <ScriptCmd>CapturePopup()<CR>
  try
    feedkeys(":\<F2>Ka \<F6>\<C-C>", 'xt')
    assert.equals(popup_text, ['▼あ', '▶ 1/2 蚊', '  2/2 家'])
    feedkeys(":\<F2>\<F4>ka\<F6>\<C-C>", 'xt')
    assert.equals(popup_text, ['ア'])
  finally
    cunmap <F6>
  endtry
}

def Toggle()
  Caskk.Toggle('commandline')
enddef

suite.activation_mapping_can_toggle_off_and_resume_native_input = (): void => {
  Setup()
  defer Cleanup()
  cnoremap <C-J> <ScriptCmd>Toggle()<CR>
  try
    const original = maparg('<C-J>', 'c', false, true)
    feedkeys(":\<C-J>Ka\<C-J>ka\<F3>\<C-C>", 'xt')
    assert.equals(captured, 'かka')
    assert.equals(enabled, false)
    assert.equals(maparg('<C-J>', 'c', false, true), original)
  finally
    cunmap <C-J>
  endtry
}

suite.typed_text_remains_visible_on_the_terminal = (): void => {
  const script = tempname() .. '.vim'
  const dictionary = tempname()
  writefile(['か /蚊/家/'], dictionary)
  defer delete(dictionary)
  const ready = tempname()
  defer delete(script)
  defer delete(ready)
  writefile([
    'vim9script',
    'set rtp^=' .. escape(getcwd(), ' ,'),
    "import autoload 'caskk.vim' as C",
    'C.Config({mode_popup_time: 0, dictionaries: [' .. string(dictionary) .. '], mappings: {"\<Space>": "Convert"}})',
    "C.RegisterInputScheme({name: 'visible', consonants: {k: 'k'}, combinations: {a: 'a'}})",
    "cnoremap <F2> <ScriptCmd>C.Enable('visible')<CR>",
    'writefile(["ready"], ' .. string(ready) .. ')',
  ], script)
  const terminal = term_start([v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-N', '-S', script],
    {hidden: true, term_rows: 12, term_cols: 40})
  try
    for _ in range(100)
      term_wait(terminal, 10)
      if filereadable(ready)
        break
      endif
    endfor
    term_sendkeys(terminal, ":\<F2>K")
    term_wait(terminal, 100)
    assert.equals(trim(term_getline(terminal, 12)), ':k')
    term_sendkeys(terminal, 'a')
    term_wait(terminal, 100)
    assert.equals(trim(term_getline(terminal, 12)), ':か')
    term_sendkeys(terminal, ' ')
    term_wait(terminal, 100)
    assert.equals(trim(term_getline(terminal, 12)), ':蚊')
    const screen = join(mapnew(range(1, 11), (_, row) => term_getline(terminal, row)), "\n")
    assert.equals(stridx(screen, '▶ 1/2 蚊') >= 0, true)
    assert.equals(stridx(screen, '2/2 家') >= 0, true)
    for kind in ['/', '?']
      term_sendkeys(terminal, "\<C-C>" .. kind .. "\<F2>ka")
      term_wait(terminal, 100)
      assert.equals(trim(term_getline(terminal, 12)), kind .. 'か')
    endfor
  finally
    job_stop(term_getjob(terminal), 'kill')
    execute 'silent! bwipeout! ' .. terminal
  endtry
}

suite.inactive_candidate_actions_use_the_input_scheme = (): void => {
  Setup()
  defer Cleanup()
  Caskk.RegisterInputScheme({name: 'commandline', consonants: {k: 'k'},
    combinations: {a: 'a', p: 'o*u'}})
  Caskk.Config({mappings: {p: 'TogglePin', P: 'ToggleDemote'}})
  for keys in ['kp', 'Kp', 'kP']
    feedkeys(":\<F2>" .. keys .. "\<F3>\<C-C>", 'xt')
    assert.equals(captured, 'こう')
  endfor
}

suite.candidate_list_is_visible_and_follows_selection = (): void => {
  Setup()
  defer Cleanup()
  const path = Dictionary()
  defer delete(path)
  cnoremap <F6> <ScriptCmd>CapturePopup()<CR>
  try
    feedkeys(":\<F2>Ka \<F6>\<C-C>", 'xt')
    assert.equals(index(popup_text, '▶ 1/2 蚊') >= 0, true)
    assert.equals(index(popup_text, '  2/2 家') >= 0, true)
    feedkeys(":\<F2>Ka  \<F6>\<C-C>", 'xt')
    assert.equals(index(popup_text, '▶ 2/2 家') >= 0, true)
    assert.equals(popup_list(), [])
    Caskk.Config({candidate_popup: false, dictionaries: [path], mappings: {"\<Space>": 'Convert'}})
    feedkeys(":\<F2>Ka \<F6>\<C-C>", 'xt')
    assert.equals(popup_text, ['▼あ'])
  finally
    cunmap <F6>
  endtry
}

suite.backspace_cancels_conversion_and_deletes_one_reading_character = (): void => {
  Setup()
  defer Cleanup()
  const path = Dictionary()
  defer delete(path)
  feedkeys(":前\<F2>Ka \<BS>\<F3>\<C-C>", 'xt')
  assert.equals(captured, '前')
  assert.equals(user_runtime.Get().GetSnapshot().mru, {})
}
