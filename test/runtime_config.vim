vim9script

import autoload 'caskk.vim' as Caskk

final suite = themis#suite('public input configuration')
const assert = themis#helper('assert')

def Setup(): list<number>
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  Caskk.Config({})
  Caskk.RegisterInputScheme({name: 'configured', consonants: {k: 'k'}, combinations: {a: 'a'}})
  return [previous, number]
enddef

def Cleanup(context: list<number>)
  try
    Caskk.Disable()
    Caskk.Config({})
  finally
    execute 'noautocmd keepalt hide buffer ' .. context[0]
    execute 'silent! bwipeout! ' .. context[1]
  endtry
enddef

def RemoveGlobalArrowMappings()
  execute 'silent! iunmap <Up>'
  execute 'silent! iunmap <Down>'
enddef

def CaptureCurrentLine()
  g:caskk_captured_lines->add(getline(1))
enddef

suite.sticky_key_and_function_key_action_are_used_by_public_enable = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Config({sticky_key: ';', mappings: {"\<F10>": 'Commit'}})
  Caskk.Enable('configured')
  feedkeys("a;ka\<F10>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前かか後')
  normal! u
  assert.equals(getline(1), '前か後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.mappings_accept_vim_keycode_expressions = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const actions = {"\<Space>": 'Convert', "\<C-N>": 'Convert', "\<C-P>": 'PreviousCandidate', "\<C-M>": 'Commit', q: 'OpenRegistration'}
  Caskk.Config({sticky_key: ';', mappings: actions})
  Caskk.Enable('configured')
  for key in ["\<Space>", "\<C-N>", "\<C-P>", "\<C-M>", 'q']
    assert.equals(maparg(key, 'i', false, true).buffer, 1)
  endfor
  feedkeys("a;ka\<C-M>\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
}

suite.ctrl_n_and_ctrl_p_navigate_candidates_through_configured_mappings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const dictionary = tempname()
  defer delete(dictionary)
  writefile(['か /蚊/家/化/'], dictionary)
  const actions = {"\<Space>": 'Convert', "\<C-N>": 'Convert', "\<C-P>": 'PreviousCandidate', "\<C-M>": 'Commit'}
  Caskk.Config({sticky_key: ';', dictionaries: [dictionary], mappings: actions})
  Caskk.Enable('configured')
  feedkeys("a;ka\<Space>\<C-N>\<C-P>\<C-M>\<Esc>", 'xt')
  assert.equals(getline(1), '前蚊後')
}

suite.ctrl_n_and_ctrl_p_candidate_mappings_work_with_insert_arrow_mappings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const dictionary = tempname()
  defer delete(dictionary)
  defer RemoveGlobalArrowMappings()
  writefile(['か /蚊/家/化/'], dictionary)
  inoremap <Up> <C-O>gk
  inoremap <Down> <C-O>gj
  inoremap <buffer> <F12> <ScriptCmd>CaptureCurrentLine()<CR>
  Caskk.Config({sticky_key: ';', dictionaries: [dictionary], mappings: {
    "\<Space>": 'Convert', "\<C-N>": 'Convert', "\<C-P>": 'PreviousCandidate', "\<C-M>": 'Commit'}})
  Caskk.Enable('configured')
  g:caskk_captured_lines = []
  feedkeys("a;ka\<Space>\<C-N>\<F12>\<C-P>\<F12>\<Esc>", 'xt')
  assert.equals(g:caskk_captured_lines, ['前家後', '前蚊後'])
  assert.equals(getline(1), '前蚊後')
  Caskk.Disable()
  assert.equals(maparg('<Up>', 'i', false, true).rhs, '<C-O>gk')
  assert.equals(maparg('<Down>', 'i', false, true).rhs, '<C-O>gj')
}

suite.mode_mappings_switch_between_modes_and_convert_abbreviations = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const dictionary = tempname()
  defer delete(dictionary)
  writefile(['apple /アップル/'], dictionary)
  const actions = {"\<F1>": 'KatakanaMode', "\<F2>": 'HalfwidthKatakanaMode',
    "\<F3>": 'FullwidthAlphanumericMode', "\<F4>": 'AbbreviationMode',
    "\<F5>": 'Commit', "\<Space>": 'Convert'}
  Caskk.Config({dictionaries: [dictionary], mappings: actions})
  Caskk.Enable('configured')
  feedkeys("a\<F1>ka\<F1>ka\<F2>ka\<F3>I like apples! Do you?\<F4>apple\<Space>\<F5>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前カかｶＩ　ｌｉｋｅ　ａｐｐｌｅｓ！　Ｄｏ　ｙｏｕ？アップルｋａ後')
}

suite.abbreviation_numeric_placeholders_convert_through_public_insert_mappings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const dictionary = tempname()
  defer delete(dictionary)
  writefile(['#:# /#0時#0分/'], dictionary)
  Caskk.Config({dictionaries: [dictionary], candidate_popup: false, mode_popup: false,
    mappings: {"\<F4>": 'AbbreviationMode', "\<Space>": 'Convert', "\<F10>": 'Commit'}})
  Caskk.Enable('configured')
  feedkeys("a\<F4>12:34\<Space>\<F10>\<Esc>", 'xt')
  assert.equals(getline(1), '前12時34分後')
}

suite.mode_actions_commit_modified_reading_in_the_target_kana_script = (): void => {
  for [key, action, expected] in [
    ["\<F1>", 'KatakanaMode', 'カ'],
    ["\<F2>", 'HalfwidthKatakanaMode', 'ｶ'],
  ]
    const context = Setup()
    try
      var mappings: dict<string> = {}
      mappings[key] = action
      Caskk.Config({sticky_key: ';', mappings: mappings})
      Caskk.Enable('configured')
      feedkeys("a;ka" .. key .. "ka\<Esc>", 'xt')
      assert.equals(getline(1), '前' .. expected .. expected .. '後')
      assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
    finally
      Cleanup(context)
    endtry
  endfor
}

suite.fullwidth_mode_action_commits_abbreviation_as_fullwidth_text = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Config({mappings: {
    "\<F3>": 'FullwidthAlphanumericMode', "\<F4>": 'AbbreviationMode'}})
  Caskk.Enable('configured')
  feedkeys("a\<F4>apple\<F3>\<Esc>", 'xt')
  assert.equals(getline(1), '前ａｐｐｌｅ後')
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
}

suite.abbreviation_commit_restores_the_mode_active_before_abbreviation = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const dictionary = tempname()
  defer delete(dictionary)
  writefile(['apple /アップル/'], dictionary)
  const actions = {"\<F1>": 'KatakanaMode', "\<F2>": 'AbbreviationMode',
    "\<Space>": 'Convert', "\<F3>": 'Commit'}
  Caskk.Config({dictionaries: [dictionary], mappings: actions})
  Caskk.Enable('configured')
  feedkeys("a\<F1>\<F2>apple\<Space>\<F3>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前アップルカ後')
}

suite.katakana_modes_render_full_okuri_when_input_continues_after_automatic_conversion = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const dictionary = tempname()
  defer delete(dictionary)
  writefile(['ほs /欲/'], dictionary)
  Caskk.RegisterInputScheme({name: 'katakana-mode-okuri',
    consonants: {k: 'k', r: 'r', g: 'g', h: 'h', s: 's'},
    combinations: {a: 'a', e: 'e', i: 'i', o: 'o', u: 'u'}})
  Caskk.Config({sticky_key: ';', dictionaries: [dictionary],
    mappings: {"\<F1>": 'KatakanaMode'}})
  Caskk.Enable('katakana-mode-okuri')
  feedkeys("a\<F1>korega;ho;sii\<Esc>", 'xt')
  assert.equals(getline(1), '前コレガ欲シイ後')
}

suite.input_mode_resets_on_insertleave_by_default_and_can_be_preserved = (): void => {
  const context = Setup()
  defer Cleanup(context)
  for [options, second_output] in [
    [{}, 'か'],
    [{persist_input_mode: true}, 'カ'],
  ]
    Caskk.Config(extend(copy(options), {mappings: {"\<F1>": 'KatakanaMode'}}))
    Caskk.Enable('configured')
    feedkeys("a\<F1>ka\<Esc>aka\<Esc>", 'xt')
    assert.equals(getline(1), '前カ' .. second_output .. '後')
    Caskk.Disable()
    setline(1, '前後')
    cursor(1, 1)
  endfor
}

suite.config_copies_mappings_and_omitted_input_fields_reset_to_defaults = (): void => {
  const context = Setup()
  defer Cleanup(context)
  final mappings = {"\<F10>": 'Commit'}
  Caskk.Config({sticky_key: ';', mappings: mappings})
  mappings["\<F10>"] = 'PreviousCandidate'
  Caskk.Enable('configured')
  feedkeys("a;ka\<F10>\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
  Caskk.Disable()
  Caskk.Config({highlight: {preedit: {cterm: 'bold'}}})
  Caskk.Enable('configured')
  assert.equals(maparg('<F10>', 'i'), '')
  feedkeys("a;ka\<Esc>", 'xt')
  assert.equals(getline(1), '前か;か後')
}

suite.config_update_releases_the_binding_and_next_enable_uses_new_settings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Config({sticky_key: ';', mappings: {"\<F10>": 'Commit'}})
  Caskk.Enable('configured')
  Caskk.Config({sticky_key: ':', mappings: {"\<F11>": 'Commit'}})
  assert.equals(Caskk.IsEnabled(), false)
  Caskk.Enable('configured')
  assert.equals(maparg('<F11>', 'i', false, true).buffer, 1)
  feedkeys("a:ka\<F11>\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
  Caskk.Disable()
  Caskk.Enable('configured')
  assert.equals(maparg('<F10>', 'i'), '')
  feedkeys("a:ka\<F11>\<Esc>", 'xt')
  assert.equals(getline(1), '前かか後')
}

suite.configuration_update_releases_bindings_in_every_buffer = (): void => {
  const first = Setup()
  const second = bufadd('')
  const configuration_buffer = bufadd('')
  bufload(second)
  bufload(configuration_buffer)
  try
    Caskk.Config({sticky_key: ';'})
    Caskk.Enable('configured')
    execute 'noautocmd keepalt hide buffer ' .. second
    setlocal buftype=nofile noswapfile
    setline(1, '前後')
    Caskk.Enable('configured')

    execute 'noautocmd keepalt hide buffer ' .. configuration_buffer
    Caskk.Config({sticky_key: ':'})
    assert.equals(bufnr('%'), configuration_buffer)
    assert.equals(Caskk.IsEnabled(), false)
    execute 'noautocmd keepalt hide buffer ' .. first[1]
    assert.equals(Caskk.IsEnabled(), false)
    assert.equals(maparg('k', 'i'), '')
  finally
    for number in [first[1], second]
      execute 'noautocmd keepalt hide buffer ' .. number
      Caskk.Disable()
    endfor
    execute 'noautocmd keepalt hide buffer ' .. first[0]
    execute 'silent! bwipeout! ' .. first[1]
    execute 'silent! bwipeout! ' .. second
    execute 'silent! bwipeout! ' .. configuration_buffer
  endtry
}

suite.invalid_input_types_keys_and_actions_preserve_all_previous_settings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Config({sticky_key: ';', mappings: {"\<F10>": 'Commit'}, highlight: {preedit: {cterm: 'bold'}}})
  const before = hlget('CaskkPreedit')
  for options in [
    {sticky_key: 1}, {sticky_key: []}, {sticky_key: 'two'},
    {sticky_key: '<NotAKey>'}, {mappings: []}, {mappings: {"\<F10>": 1}},
    {keyboard_layout: 1}, {keyboard_layout: 'UK'},
    {keyboard_layout_overrides: []},
    {keyboard_layout_overrides: {1: '??'}},
    {keyboard_layout_overrides: {1: 2}},
    {keyboard_layout_overrides: {1: '?', 2: '?'}},
    {mappings: {"\<F10>": 'MissingAction'}}, {mappings: {'<F10>': 'Commit'}},
    {mappings: {'two': 'Commit'}},
    {mappings: {'<NotAKey>': 'Commit'}},
    {persist_input_mode: 'yes'},
    {small_tsu_okuri_as_t: 'yes'},
    {registration_inline: 'yes'},
    {mode_popup: 'yes'},
    {mode_popup_labels: []},
    {mode_popup_labels: {unknown: 'x'}},
    {mode_popup_labels: {katakana: ''}},
    {mode_popup_labels: {katakana: 1}},
    {mode_popup_markers: []},
    {mode_popup_markers: {unknown: 'x'}},
    {mode_popup_markers: {modified: 1}},
    {mode_popup_time: -1},
    {mode_popup_time: '1000'},
    {sticky_key: ':', highlight: []}, {highlight: {preedit: []}},
    {highlight: {preedit: {cterm: 1}}},
  ]
    var caught = ''
    try
      Caskk.Config(options)
    catch
      caught = v:exception
    endtry
    assert.equals(stridx(caught, 'caskk: invalid configuration:'), 0)
    assert.equals(hlget('CaskkPreedit'), before)
  endfor
  Caskk.Enable('configured')
  feedkeys("a;ka\<F10>\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
}

suite.invalid_highlight_color_does_not_replace_input_settings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Config({sticky_key: ';', mappings: {"\<F10>": 'Commit'}})
  const before = hlget('CaskkPreedit')
  var caught = ''
  try
    Caskk.Config({sticky_key: ':', mappings: {"\<F11>": 'Commit'},
      highlight: {preedit: {ctermfg: 'caskk-invalid-color'}}})
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: invalid configuration:'), 0)
  assert.equals(hlget('CaskkPreedit'), before)
  Caskk.Enable('configured')
  assert.equals(maparg('<F11>', 'i'), '')
  feedkeys("a;ka\<F10>\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
}

suite.named_sticky_key_and_explicit_enter_action_use_real_keycodes = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Config({sticky_key: '<F9>', mappings: {"\<CR>": 'Commit'}})
  Caskk.Enable('configured')
  feedkeys("a\<F9>ka\<CR>ka\<Esc>", 'xt')
  assert.equals(getline(1, '$'), ['前かか後'])
}

suite.small_tsu_dictionary_prefix_is_enabled_by_default_and_can_be_disabled = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['けっt /蹴/', 'けx /標準/'], path)
  Caskk.RegisterInputScheme({name: 'small-tsu-prefix', consonants: {k: 'k'}, combinations: {q: 'e*Tte'}})

  for [options, expected] in [
    [{dictionaries: [path]}, '前蹴って後'],
    [{dictionaries: [path], small_tsu_okuri_as_t: false}, '前標準って後'],
  ]
    setline(1, '前後')
    cursor(1, 1)
    Caskk.Config(options)
    Caskk.Enable('small-tsu-prefix')
    feedkeys("aKQ\<Esc>", 'xt')
    assert.equals(getline(1), expected)
    Caskk.Disable()
  endfor
}

suite.keyboard_layout_config_maps_shifted_number_row_to_okuri_boundary = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['けっt /蹴/'], path)
  Caskk.RegisterInputScheme({name: 'layout-okuri', consonants: {k: 'k'},
    combinations: {1: 'e*Tte', 2: 'e*Tte'}})
  Caskk.Config({keyboard_layout: 'US', dictionaries: [path]})
  Caskk.Enable('layout-okuri')
  cursor(1, 1)
  feedkeys("ak!\<Esc>", 'xt')
  assert.equals(getline(1), '前蹴って後')
  Caskk.Disable()

  setline(1, '前後')
  Caskk.Config({keyboard_layout: 'JIS', dictionaries: [path]})
  Caskk.Enable('layout-okuri')
  cursor(1, 1)
  feedkeys("ak\"\<Esc>", 'xt')
  assert.equals(getline(1), '前蹴って後')
}

suite.keyboard_layout_override_replaces_one_shifted_symbol_through_public_config = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['けっt /蹴/'], path)
  Caskk.RegisterInputScheme({name: 'layout-override-okuri', consonants: {k: 'k'},
    combinations: {1: 'e*Tte', 2: 'e*Tte'}})
  var overrides = {1: '?'}
  Caskk.Config({keyboard_layout: 'US', keyboard_layout_overrides: overrides, dictionaries: [path]})
  overrides['1'] = '!'
  Caskk.Enable('layout-override-okuri')
  cursor(1, 1)
  feedkeys("ak?\<Esc>", 'xt')
  assert.equals(getline(1), '前蹴って後')
}
