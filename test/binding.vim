vim9script

import autoload 'caskk/binding.vim' as binding
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('buffer-local IME bindings')
const assert = themis#helper('assert')
var captured_preedit_positions: list<number> = []
var captured_preedit_highlights: list<number> = []
var captured_preedit_text: list<string> = []

def CapturePreeditPosition()
  captured_preedit_positions->add(col('.'))
  captured_preedit_highlights->add(len(prop_list(1, {types: ['caskk_preedit']})))
  captured_preedit_text->add(getline(1))
enddef

def Setup(): list<number>
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  return [previous, number]
enddef

def Cleanup(context: list<number>)
  execute 'noautocmd keepalt hide buffer ' .. context[0]
  execute 'silent! bwipeout! ' .. context[1]
enddef

def CapturePendingBuffer()
  g:caskk_pending_snapshot = getline(1)
  g:caskk_pending_properties = prop_list(1, {types: ['caskk_preedit']})
  g:caskk_pending_has_okuri_marker = false
  g:caskk_pending_marker_column = 0
  for property in g:caskk_pending_properties
    if get(property, 'text', '') ==# '*'
      g:caskk_pending_has_okuri_marker = true
      g:caskk_pending_marker_column = property.col
    endif
  endfor
enddef

def CaptureBindingState()
  const request = binding.GetRegistrationRequest()
  g:caskk_binding_snapshots->add([
    getline(1), request is null_object ? '' : request.reading,
  ])
enddef

suite.backspace_deletes_pending_key_then_modifier_then_native_text = (): void => {
  for prefix in ['K', ';k']
    const context = Setup()
    try
      const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
      keys.Enable()
      feedkeys("afoo" .. prefix .. "\<BS>\<BS>\<BS>\<Esc>", 'xt')
      assert.equals(getline(1), '前fo後')
      assert.equals(keys.GetEditor() is null_object, true)
      keys.Disable()
    finally
      Cleanup(context)
    endtry
  endfor
}

suite.backspace_keeps_the_shortened_reading_convertible = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('あいうえ /読み/')]])
  const compiled = scheme.Compile({}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'})
  const keys = binding.Binding.new(compiled, ';', entries, null_object,
    {c: 'Convert'})
  keys.Enable()
  feedkeys("a;aiueo\<BS>c\<Esc>", 'xt')
  assert.equals(getline(1), '前読み後')
  keys.Disable()
}

suite.backspace_displays_only_the_last_preedit_character_as_deleted = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('あいうえ /読み/')]])
  const compiled = scheme.Compile({}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'})
  const keys = binding.Binding.new(compiled, ';', entries, null_object, {c: 'Convert'})
  inoremap <buffer> <F11> <ScriptCmd>CapturePendingBuffer()<CR>
  keys.Enable()
  feedkeys("a;aiueo\<BS>\<F11>c\<Esc>", 'xt')
  assert.equals(g:caskk_pending_snapshot, '前あいうえ後')
  assert.equals(empty(g:caskk_pending_properties), false)
  assert.equals(getline(1), '前読み後')
  iunmap <buffer> <F11>
  keys.Disable()
}

suite.ordinary_input_after_preedit_backspace_stays_in_the_reading = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({k: 'k'}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'})
  const keys = binding.Binding.new(compiled, ';')
  inoremap <buffer> <F11> <ScriptCmd>CapturePendingBuffer()<CR>
  keys.Enable()
  feedkeys("a;aiueo\<BS>kakikukeko\<F11>\<Esc>", 'xt')
  assert.equals(g:caskk_pending_snapshot, '前あいうえかきくけこ後')
  assert.equals(empty(g:caskk_pending_properties), false)
  assert.equals(g:caskk_pending_has_okuri_marker, false)
  iunmap <buffer> <F11>
  keys.Disable()
}

suite.pending_consonant_is_visible_until_its_vowel_completes_the_kana = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()

  inoremap <buffer> <F12> <ScriptCmd>CapturePendingBuffer()<CR>
  feedkeys("ak\<F12>a\<Esc>", 'xt')
  assert.equals(g:caskk_pending_snapshot, '前k後')
  assert.equals(g:caskk_pending_properties, [])
  assert.equals(getline(1), '前か後')

  iunmap <buffer> <F12>
  keys.Disable()
}

suite.unmodified_latent_boundary_keeps_following_kana_direct = (): void => {
  for [following, expected] in [['ka', 'こうか'], ['i', 'こうい']]
    const context = Setup()
    try
      const compiled = scheme.Compile({k: 'k', p: 'p'}, {a: 'a', p: 'o*u', i: 'i'})
      const keys = binding.Binding.new(compiled, ';')
      inoremap <buffer> <F11> <ScriptCmd>CapturePendingBuffer()<CR>
      keys.Enable()
      feedkeys("akp" .. following .. "\<F11>\<Esc>", 'xt')
      assert.equals(g:caskk_pending_snapshot, '前' .. expected .. '後')
      assert.equals(g:caskk_pending_properties, [])
      iunmap <buffer> <F11>
      keys.Disable()
    finally
      Cleanup(context)
    endtry
  endfor
}

suite.modified_input_after_unmodified_latent_boundary_starts_preedit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({k: 'k', p: 'p'}, {p: 'o*u', i: 'i'})
  const keys = binding.Binding.new(compiled, ';')
  inoremap <buffer> <F11> <ScriptCmd>CapturePendingBuffer()<CR>
  keys.Enable()
  feedkeys("akp;i\<F11>\<Esc>", 'xt')
  assert.equals(g:caskk_pending_snapshot, '前こうい後')
  assert.equals(empty(g:caskk_pending_properties), false)
  iunmap <buffer> <F11>
  keys.Disable()
}

suite.modified_small_tsu_consonant_starts_okuri_in_preedit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({s: 's', l: 'T'}, {i: 'i'},
    [scheme.SpecialDefinition.new(['l'], 'っ')])
  const keys = binding.Binding.new(compiled, ';')
  inoremap <buffer> <F11> <ScriptCmd>CapturePendingBuffer()<CR>
  keys.Enable()
  feedkeys("aSiL\<F11>\<Esc>", 'xt')
  assert.equals(g:caskk_pending_snapshot, '前しっ後')
  assert.equals(g:caskk_pending_has_okuri_marker, true)
  assert.equals(g:caskk_pending_marker_column, 7)
  iunmap <buffer> <F11>
  keys.Disable()
}

suite.unmodified_small_tsu_special_keeps_its_direct_output = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({s: 's', l: 'T'}, {i: 'i'},
    [scheme.SpecialDefinition.new(['l'], 'っ')])
  const keys = binding.Binding.new(compiled, ';')
  keys.Enable()
  feedkeys("al\<Esc>", 'xt')
  assert.equals(getline(1), '前っ後')
  keys.Disable()
}

suite.nonconsonant_combination_key_is_literal_in_direct_state = (): void => {
  for key in ['1', '!']
    const context = Setup()
    try
      const compiled = scheme.Compile({k: 'k'}, {a: 'a', '1': 'e*Tte', '!': 'ka'})
      const keys = binding.Binding.new(compiled)
      inoremap <buffer> <F11> <ScriptCmd>CapturePendingBuffer()<CR>
      keys.Enable()
      feedkeys("a" .. key .. "\<F11>\<Esc>", 'xt')
      assert.equals(g:caskk_pending_snapshot, '前' .. key .. '後')
      assert.equals(g:caskk_pending_properties, [])
      iunmap <buffer> <F11>
      keys.Disable()
    finally
      Cleanup(context)
    endtry
  endfor
}

suite.multi_key_consonant_prefixes_resolve_before_combinations = (): void => {
  for [text, expected] in [['wgi', 'うぃ'], ['wga', 'うぁ'], ['wa', 'わ']]
    const context = Setup()
    try
      const compiled = scheme.Compile({w: 'w', g: 'g', wg: 'wh'},
        {a: 'a', g: 'i*ta', i: 'i'})
      const keys = binding.Binding.new(compiled)
      inoremap <buffer> <F11> <ScriptCmd>CapturePendingBuffer()<CR>
      keys.Enable()
      feedkeys("a" .. text .. "\<F11>\<Esc>", 'xt')
      assert.equals(g:caskk_pending_snapshot, '前' .. expected .. '後')
      assert.equals(g:caskk_pending_properties, [])
      iunmap <buffer> <F11>
      keys.Disable()
    finally
      Cleanup(context)
    endtry
  endfor
}

suite.backspace_without_pending_input_uses_native_multibyte_deletion = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  feedkeys("aka\<BS>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
  keys.Disable()
}

suite.backspace_preserves_restored_modifier_for_following_input = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';', entries, null_object, {s: 'Convert'})
  keys.Enable()
  feedkeys("afooK\<BS>kas\<Esc>", 'xt')
  assert.equals(getline(1), '前foo蚊後')
  keys.Disable()
}

suite.explicit_backspace_special_precedes_default_deletion = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['<BS>'], '戻')]))
  keys.Enable()
  feedkeys("afoo\<BS>\<Esc>", 'xt')
  assert.equals(getline(1), '前foo戻後')
  keys.Disable()
}

suite.backspace_edits_the_preedit_before_following_input_converts_it = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('かか /科科/')]])
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, null_object, {s: 'Convert'})
  keys.Enable()
  feedkeys("aKaka\<BS>kas\<Esc>", 'xt')
  assert.equals(getline(1), '前科科後')
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  assert.equals(keys.GetEditor() is null_object, true)
  keys.Disable()
}

suite.backspace_commits_okuri_candidate_and_learns_its_body_before_native_deletion = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const preferences = user_state.State.new()
  const compiled = scheme.Compile({k: 'k'}, {a: 'a', u: 'u'}, [scheme.SpecialDefinition.new(['i'], 'い')])
  const keys = binding.Binding.new(compiled, '', entries, preferences)
  keys.Enable()
  feedkeys("aIKu\<BS>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前行か後')
  assert.equals(preferences.GetSnapshot().mru[json_encode(['い', 'く'])], ['行'])
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  assert.equals(keys.GetEditor() is null_object, true)
  keys.Disable()
}

suite.backspace_bypasses_existing_remap_while_enabled_and_restores_it_on_disable = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <silent> <nowait> <BS> 旧
  const before = maparg('<BS>', 'i', false, true)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
  keys.Enable()
  feedkeys("afooK\<BS>\<BS>\<BS>\<Esc>", 'xt')
  assert.equals(getline(1), '前fo後')
  keys.Disable()
  const restored = maparg('<BS>', 'i', false, true)
  assert.equals(restored.rhs, before.rhs)
  assert.equals(restored.silent, before.silent)
  assert.equals(restored.nowait, before.nowait)
  feedkeys("a\<BS>\<Esc>", 'xt')
  assert.equals(getline(1), '前fo旧後')
}

suite.backspace_handoff_keeps_native_deletion_and_direct_input_as_separate_undo_units = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
  keys.Enable()
  feedkeys("afooK\<BS>\<BS>\<BS>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前foか後')
  for expected in ['前fo後', '前foo後', '前後']
    normal! u
    assert.equals(getline(1), expected)
    assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
    assert.equals(keys.GetEditor() is null_object, true)
  endfor
  for expected in ['前foo後', '前fo後', '前foか後']
    execute "normal! \<C-r>"
    assert.equals(getline(1), expected)
  endfor
  keys.Disable()
}

suite.backspace_candidate_handoff_preserves_reading_checkpoint_through_undo_and_redo = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const preferences = user_state.State.new()
  const compiled = scheme.Compile({k: 'k'}, {a: 'a', u: 'u'}, [scheme.SpecialDefinition.new(['i'], 'い')])
  const keys = binding.Binding.new(compiled, '', entries, preferences)
  keys.Enable()
  feedkeys("aIKu\<BS>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前行か後')
  for expected in ['前行後', '前行く後', '前いく後', '前後']
    normal! u
    assert.equals(getline(1), expected)
    assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
    assert.equals(keys.GetEditor() is null_object, true)
  endfor
  for expected in ['前いく後', '前行く後', '前行後', '前行か後']
    execute "normal! \<C-r>"
    assert.equals(getline(1), expected)
    assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  endfor
  assert.equals(preferences.GetSnapshot().mru[json_encode(['い', 'く'])], ['行'])
  keys.Disable()
}

suite.enable_installs_keys_and_actions_and_insertleave_closes_preedit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const actions = {s: 'Convert', n: 'NextCandidate', c: 'Commit'}
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';', entries, user_state.State.new(), actions)
  keys.Enable()
  assert.equals(keys.IsEnabled(), true)
  assert.equals(maparg('k', 'i', false, true).buffer, 1)
  feedkeys("aKasnc\<Esc>", 'xt')
  assert.equals(getline(1), '前科後')
  assert.equals(col('.'), 4)
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  assert.equals(keys.GetEditor() is null_object, true)
  keys.Disable()
  assert.equals(maparg('k', 'i'), '')
  assert.equals(keys.IsEnabled(), false)
}

suite.convert_mapping_starts_advances_and_requests_registration_after_last_candidate = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries,
    user_state.State.new(), {'<Space>': 'Convert'})
  g:caskk_binding_snapshots = []
  inoremap <buffer> <F11> <ScriptCmd>CaptureBindingState()<CR>
  inoremap <buffer> <F12> <ScriptCmd>CaptureBindingState()<CR>
  keys.Enable()
  feedkeys("aKa\<Space>\<Space>\<F11>\<Space>\<F12>\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
  assert.equals(g:caskk_binding_snapshots, [['前科後', ''], ['前か後', 'か']])
  keys.Disable()
  unlet! g:caskk_binding_snapshots
}

suite.tab_after_candidate_selection_commits_then_inserts_a_native_tab = (): void => {
  const context = Setup()
  defer Cleanup(context)
  setlocal noexpandtab
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries,
    null_object, {s: 'Convert'})
  keys.Enable()
  feedkeys("aKas\<Tab>\<Esc>", 'xt')
  assert.equals(getline(1), "前蚊\t後")
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  keys.Disable()
}

suite.modified_standalone_vowel_does_not_modify_input_after_okuri_candidate_commit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('あまi /甘/')]])
  const compiled = scheme.Compile({m: 'm'}, {a: 'a', m: 'a*ku', i: 'i'})
  const keys = binding.Binding.new(compiled, ';', entries, null_object, {'<Space>': 'Convert'})
  inoremap <buffer> <F11> <ScriptCmd>CapturePendingBuffer()<CR>
  keys.Enable()
  feedkeys("a;ama;i\<Space>amai\<F11>\<Esc>", 'xt')
  assert.equals(g:caskk_pending_snapshot, '前甘いあまい後')
  assert.equals(g:caskk_pending_properties, [])
  assert.equals(getline(1), '前甘いあまい後')
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  iunmap <buffer> <F11>
  keys.Disable()
}

suite.unmodified_okuri_suffix_continues_directly_after_candidate_commit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('むずかs /難/')]])
  const compiled = scheme.Compile({m: 'm', z: 'z', k: 'k', s: 's'}, {u: 'u', a: 'a', i: 'i'})
  const keys = binding.Binding.new(compiled, ';', entries)
  inoremap <buffer> <F11> <ScriptCmd>CapturePendingBuffer()<CR>
  keys.Enable()
  feedkeys("a;muzuka;sii\<F11>\<Esc>", 'xt')
  assert.equals(g:caskk_pending_snapshot, '前難しい後')
  assert.equals(g:caskk_pending_properties, [])
  assert.equals(getline(1), '前難しい後')
  iunmap <buffer> <F11>
  keys.Disable()
}

suite.unavailable_printable_actions_fall_back_to_ordinary_input = (): void => {
  const actions = {'<Space>': 'Convert', n: 'NextCandidate', p: 'PreviousCandidate', c: 'Commit', r: 'OpenRegistration'}
  for [key, action] in items(actions)
    const context = Setup()
    try
      final configured: dict<string> = {}
      configured[key] = action
      const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', {},
        null_object, configured)
      keys.Enable()
      feedkeys('a' .. (key ==# '<Space>' ? "\<Space>" : key) .. "\<Esc>", 'xt')
      assert.equals(getline(1), '前' .. (key ==# '<Space>' ? ' ' : key) .. '後')
      keys.Disable()
    finally
      Cleanup(context)
    endtry
  endfor
}

suite.start_conversion_mapping_falls_back_while_only_a_consonant_is_pending = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({z: 'z'}, {z: 'a*N'}), '', {},
    null_object, {'<Space>': 'Convert'})
  keys.Enable()
  feedkeys("az\<Space>\<Space>\<Esc>", 'xt')
  assert.equals(getline(1), '前z  後')
  keys.Disable()
}

suite.unavailable_special_key_action_falls_back_to_vim_input = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <F7> Vim
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', {},
    null_object, {'<F7>': 'NextCandidate'})
  keys.Enable()
  feedkeys("a\<F7>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前Vimか後')
  assert.equals(keys.GetEditor() is null_object, true)
  keys.Disable()
}

suite.local_expression_mapping_is_restored_with_its_original_flags = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <silent> <nowait> <expr> k '旧'
  const before = maparg('k', 'i', false, true)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  keys.Enable()
  keys.Disable()
  keys.Disable()
  const restored = maparg('k', 'i', false, true)
  assert.equals(restored.rhs, before.rhs)
  assert.equals(restored.expr, before.expr)
  assert.equals(restored.silent, before.silent)
  assert.equals(restored.nowait, before.nowait)
  assert.equals(restored.sid, before.sid)
  assert.equals(restored.scriptversion, before.scriptversion)
  feedkeys("ak\<Esc>", 'xt')
  assert.equals(getline(1), '前旧後')
}

suite.global_mappings_are_not_modified_by_buffer_local_overrides = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const before = maparg('<F10>', 'i', false, true)
  inoremap <F10> 全
  const keys = binding.Binding.new(scheme.Compile({'<F10>': 'k'}, {a: 'a'}))
  try
    keys.Enable()
    keys.Disable()
    assert.equals(maparg('<F10>', 'i', false, true).buffer, 0)
    assert.equals(maparg('<F10>', 'i'), '全')
  finally
    iunmap <F10>
    if !empty(before)
      mapset('i', false, before)
    endif
  endtry
}

suite.user_changes_during_enable_are_not_overwritten_on_disable = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> k 旧
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  inoremap <buffer> k 新
  keys.Disable()
  assert.equals(maparg('k', 'i'), '新')
}

suite.reentering_insert_mode_uses_a_fresh_cursor_and_session = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  feedkeys("aKa\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
  cursor(1, 1)
  feedkeys("ika\<Esc>", 'xt')
  assert.equals(getline(1), 'か前か後')
  keys.Disable()
}

suite.quoted_bar_and_named_keys_are_passed_without_command_interpretation = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['|'], '縦'),
    scheme.SpecialDefinition.new(["'"], '引'),
    scheme.SpecialDefinition.new(['\'], '斜'),
    scheme.SpecialDefinition.new(['<'], '小'),
    scheme.SpecialDefinition.new(['<F10>'], '鍵'),
  ])
  const keys = binding.Binding.new(compiled)
  keys.Enable()
  feedkeys("a|'" .. nr2char(92) .. "<\<F10>\<Esc>", 'xt')
  assert.equals(getline(1), '前縦引斜小鍵後')
  keys.Disable()
}

suite.buffer_wipeout_releases_binding_ownership = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  execute 'bwipeout! ' .. context[1]
  assert.equals(keys.IsEnabled(), false)
}

suite.invalid_action_is_rejected_before_overriding_existing_mappings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> k 旧
  var caught = ''
  try
    const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', {}, null_object, {s: 'Unknown'})
    keys.Enable()
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: unknown binding action: Unknown')
  assert.equals(maparg('k', 'i'), '旧')
}

suite.named_key_expression_mappings_preserve_raw_keycodes_when_restored = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <expr> <F10> '旧'
  const before = maparg('<F10>', 'i', false, true)
  const keys = binding.Binding.new(scheme.Compile({'<F10>': 'k'}, {a: 'a'}))
  keys.Enable()
  keys.Disable()
  const restored = maparg('<F10>', 'i', false, true)
  assert.equals(restored.lhsraw, before.lhsraw)
  assert.equals(restored.rhs, before.rhs)
  assert.equals(restored.expr, before.expr)
  feedkeys("a\<F10>\<Esc>", 'xt')
  assert.equals(getline(1), '前旧後')
}

suite.duplicate_physical_keys_roll_back_partially_installed_mappings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <Space> 旧
  const compiled = scheme.Compile({}, {' ': 'a', '<Space>': 'i'})
  const keys = binding.Binding.new(compiled)
  var caught = ''
  try
    keys.Enable()
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: duplicate physical mapping:'), 0)
  assert.equals(keys.IsEnabled(), false)
  assert.equals(maparg('<Space>', 'i'), '旧')
}

suite.literal_fallback_handles_uppercase_and_sticky_input_without_errors = (): void => {
  for input in ['Kx', ';kx']
    const context = Setup()
    defer Cleanup(context)
    const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
    keys.Enable()
    feedkeys('a' .. input .. "\<Esc>", 'xt')
    assert.equals(getline(1), '前kx後')
    assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
    normal! u
    assert.equals(getline(1), '前後')
    keys.Disable()
  endfor
}

suite.literal_punctuation_is_included_in_the_reading_and_its_undo_checkpoint = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('か? /可疑/')]])
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, null_object, {s: 'Convert', c: 'Commit'})
  keys.Enable()
  feedkeys("aKa?sc\<Esc>", 'xt')
  assert.equals(getline(1), '前可疑後')
  normal! u
  assert.equals(getline(1), '前か?後')
  normal! u
  assert.equals(getline(1), '前後')
  keys.Disable()
}

suite.special_question_mark_takes_precedence_over_us_shift_normalization = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({}, {'/': 'e*ki'},
    [scheme.SpecialDefinition.new(['?'], '？')])
  const keys = binding.Binding.new(compiled, '', {}, null_object, {}, '', false, true, 'US', {1: '?'})
  keys.Enable()
  feedkeys("a?\<Esc>", 'xt')
  assert.equals(getline(1), '前？後')
  keys.Disable()
}

suite.unfinished_modified_input_is_inserted_as_lowercase_on_insertleave = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  feedkeys("aK\<Esc>", 'xt')
  assert.equals(getline(1), '前k後')
  assert.equals(col('.'), 4)
  assert.equals(keys.GetEditor() is null_object, true)
  keys.Disable()
}

suite.explicit_named_printable_keys_take_precedence_over_literal_fallback_maps = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['<Space>'], '空')])
  const keys = binding.Binding.new(compiled)
  keys.Enable()
  feedkeys("a\<Space>\<Esc>", 'xt')
  assert.equals(getline(1), '前空後')
  keys.Disable()
}

suite.non_ascii_input_stays_in_preedit_before_following_conversion_keys = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('かあ? /仮名/')]])
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, null_object, {s: 'Convert', c: 'Commit'})
  keys.Enable()
  feedkeys("aKaあ?sc\<Esc>", 'xt')
  assert.equals(getline(1), '前仮名後')
  normal! u
  assert.equals(getline(1), '前かあ?後')
  keys.Disable()
}

suite.non_ascii_direct_input_keeps_its_order_with_mapped_combinations = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  feedkeys("aあka漢ka\<Esc>", 'xt')
  assert.equals(getline(1), '前あか漢か後')
  normal! u
  assert.equals(getline(1), '前後')
  keys.Disable()
}

suite.left_arrow_stays_in_preedit_and_following_input_continues_at_its_end = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  captured_preedit_positions = []
  captured_preedit_text = []
  inoremap <buffer> <F12> <ScriptCmd>CapturePreeditPosition()<CR>
  keys.Enable()
  feedkeys("aKa\<Left>\<F12>ka\<F12>\<Esc>", 'xt')
  assert.equals(captured_preedit_positions, [4, 10])
  assert.equals(captured_preedit_text, ['前か後', '前かか後'])
  assert.equals(getline(1), '前かか後')
  assert.equals(col('.'), 7)
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  normal! u
  assert.equals(getline(1), '前後')
  keys.Disable()
  iunmap <buffer> <F12>
}

suite.enter_commits_reading_then_inserts_a_native_line_break = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  feedkeys("aKa\<CR>ka\<Esc>", 'xt')
  assert.equals(getline(1, '$'), ['前か', 'か後'])
  assert.equals(keys.GetEditor() is null_object, true)
  keys.Disable()
}

suite.native_movement_commits_and_learns_the_selected_candidate = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const preferences = user_state.State.new()
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, preferences, {s: 'Convert', n: 'NextCandidate'})
  keys.Enable()
  feedkeys("aKasn\<Left>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前か科後')
  assert.equals(preferences.GetSnapshot().mru[json_encode(['か', ''])], ['科'])
  keys.Disable()
}

suite.native_handoff_does_not_lose_an_unfinished_modified_consonant = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  feedkeys("aK\<Left>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前かk後')
  keys.Disable()
}

suite.standalone_vowel_after_direct_syllables_stays_direct_in_insert_mode = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({h: 'h', g: 'g'}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'})
  const keys = binding.Binding.new(compiled)
  captured_preedit_positions = []
  captured_preedit_highlights = []
  captured_preedit_text = []
  inoremap <buffer> <F12> <ScriptCmd>CapturePreeditPosition()<CR>
  keys.Enable()
  feedkeys("ahogea\<F12>\<Esc>", 'xt')
  assert.equals(getline(1), '前ほげあ後')
  assert.equals(captured_preedit_highlights, [0])
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  iunmap <buffer> <F12>
  keys.Disable()
}

suite.explicit_enter_alias_definition_precedes_native_enter_handoff = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['<Enter>'], '改')])
  const keys = binding.Binding.new(compiled)
  keys.Enable()
  feedkeys("a\<CR>\<Esc>", 'xt')
  assert.equals(getline(1, '$'), ['前改後'])
  keys.Disable()
}

suite.right_arrow_before_ime_input_preserves_native_motion = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  feedkeys("a\<Right>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前後か')
  keys.Disable()
}

suite.left_and_right_move_only_inside_a_modified_preedit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const compiled = scheme.Compile({}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'})
  const keys = binding.Binding.new(compiled, ';')
  captured_preedit_positions = []
  captured_preedit_highlights = []
  inoremap <buffer> <F12> <ScriptCmd>CapturePreeditPosition()<CR>
  keys.Enable()
  feedkeys("a;aiueo\<Left>\<F12>\<Left>\<Left>\<Left>\<Left>\<Left>\<F12>\<Left>\<F12>\<Right>\<Right>\<Right>\<Right>\<Right>\<Right>\<F12>\<Right>\<F12>\<Esc>", 'xt')
  assert.equals(captured_preedit_positions, [16, 4, 4, 19, 19])
  assert.equals(mapnew(captured_preedit_highlights, (_, count) => count > 0), [true, true, true, true, true])
  assert.equals(getline(1), '前あいうえお後')
  iunmap <buffer> <F12>
  keys.Disable()
}

suite.vertical_motion_commits_modified_text_and_clears_its_highlight = (): void => {
  const context = Setup()
  defer Cleanup(context)
  setline(1, ['前後', '別行'])
  const compiled = scheme.Compile({}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'})
  const keys = binding.Binding.new(compiled, ';')
  keys.Enable()
  feedkeys("a;aiueo\<Down>", 'xt')
  assert.equals(keys.GetEditor() is null_object, true)
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  assert.equals(getline(1, '$'), ['前あいうえお後', '別行'])
  keys.Disable()
}

suite.external_cursor_motion_to_another_line_commits_the_modified_range = (): void => {
  const context = Setup()
  defer Cleanup(context)
  setline(1, ['前後', '別行'])
  const compiled = scheme.Compile({}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'})
  const keys = binding.Binding.new(compiled, ';')
  inoremap <buffer> <F11> <C-O>j
  keys.Enable()
  feedkeys("a;aiueo\<F11>", 'xt')
  assert.equals(keys.GetEditor() is null_object, true)
  assert.equals(line('.'), 2)
  assert.equals(col('.'), 4)
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  assert.equals(getline(1, '$'), ['前あいうえお後', '別行'])
  iunmap <buffer> <F11>
  keys.Disable()
}

suite.explicit_enter_commit_action_precedes_native_line_break = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', {}, null_object, {'<CR>': 'Commit'})
  keys.Enable()
  feedkeys("aKa\<CR>ka\<Esc>", 'xt')
  assert.equals(getline(1, '$'), ['前かか後'])
  keys.Disable()
}
