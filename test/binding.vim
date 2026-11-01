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
