vim9script

import autoload 'caskk/binding.vim' as binding
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('buffer-local IME bindings')
const assert = themis#helper('assert')

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
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';', entries, null_object, {s: 'StartConversion'})
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

suite.backspace_commits_reading_and_following_input_starts_in_direct_mode = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const entries = merger.Merge([[parser.ParseLine('かか /科科/')]])
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, null_object, {s: 'StartConversion'})
  keys.Enable()
  feedkeys("aKaka\<BS>kas\<Esc>", 'xt')
  assert.equals(getline(1), '前かか後')
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
  const actions = {s: 'StartConversion', n: 'NextCandidate', c: 'Commit'}
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
  const compiled = scheme.Compile({' ': 'k'}, {'<Space>': 'a'})
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
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, null_object, {s: 'StartConversion', c: 'Commit'})
  keys.Enable()
  feedkeys("aKa?sc\<Esc>", 'xt')
  assert.equals(getline(1), '前可疑後')
  normal! u
  assert.equals(getline(1), '前か?後')
  normal! u
  assert.equals(getline(1), '前後')
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
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, null_object, {s: 'StartConversion', c: 'Commit'})
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

suite.left_arrow_commits_reading_and_restarts_input_at_the_native_cursor = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  keys.Enable()
  feedkeys("aKa\<Left>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前かか後')
  assert.equals(col('.'), 4)
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  normal! u
  assert.equals(getline(1), '前か後')
  normal! u
  assert.equals(getline(1), '前後')
  keys.Disable()
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
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, preferences, {s: 'StartConversion', n: 'NextCandidate'})
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

suite.explicit_enter_commit_action_precedes_native_line_break = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const keys = binding.Binding.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', {}, null_object, {'<CR>': 'Commit'})
  keys.Enable()
  feedkeys("aKa\<CR>ka\<Esc>", 'xt')
  assert.equals(getline(1, '$'), ['前かか後'])
  keys.Disable()
}
