vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/scheme.vim' as scheme

final suite = themis#suite('public buffer lifecycle API')
const assert = themis#helper('assert')

def Setup(): list<number>
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  Caskk.RegisterInputScheme('lifecycle', {k: 'k'}, {a: 'a'})
  return [previous, number]
enddef

def Cleanup(context: list<number>)
  execute 'noautocmd keepalt hide buffer ' .. context[0]
  execute 'silent! bwipeout! ' .. context[1]
enddef

def DisableCurrent()
  Caskk.Disable()
enddef

def EnableCurrent()
  Caskk.Enable('lifecycle')
enddef

suite.enable_and_disable_are_idempotent_and_restore_previous_mapping = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <silent> <nowait> k 旧
  const before = maparg('k', 'i', false, true)
  assert.equals(Caskk.IsEnabled(), false)
  Caskk.Enable('lifecycle')
  Caskk.Enable('lifecycle')
  assert.equals(Caskk.IsEnabled(), true)
  feedkeys("aka\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
  Caskk.Disable()
  Caskk.Disable()
  assert.equals(Caskk.IsEnabled(), false)
  const restored = maparg('k', 'i', false, true)
  assert.equals(restored.rhs, before.rhs)
  assert.equals(restored.silent, before.silent)
  assert.equals(restored.nowait, before.nowait)
  feedkeys("ak\<Esc>", 'xt')
  assert.equals(getline(1), '前か旧後')
}

suite.disable_during_insert_commits_reading_and_restores_native_input = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <F2> <ScriptCmd>DisableCurrent()<CR>
  Caskk.Enable('lifecycle')
  feedkeys("aKa\<F2>ka\<Esc>", 'xt')
  assert.equals(Caskk.IsEnabled(), false)
  assert.equals(getline(1), '前かka後')
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  assert.equals(maparg('k', 'i'), '')
}

suite.enable_during_insert_accepts_input_at_the_current_position = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <F3> <ScriptCmd>EnableCurrent()<CR>
  feedkeys("a\<F3>Ka\<Esc>", 'xt')
  assert.equals(Caskk.IsEnabled(), true)
  assert.equals(getline(1), '前か後')
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  Caskk.Disable()
}

suite.reenable_keeps_the_active_scheme_until_disabled = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.RegisterInputScheme('lifecycle-other', {k: 'n'}, {a: 'a'})
  Caskk.Enable('lifecycle')
  Caskk.Enable('lifecycle-other')
  feedkeys("aka\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
  Caskk.Disable()
  Caskk.Enable('lifecycle-other')
  feedkeys("aka\<Esc>", 'xt')
  assert.equals(getline(1), '前かな後')
  Caskk.Disable()
}

suite.reregistered_scheme_is_used_after_disable_and_reenable = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Enable('lifecycle')
  feedkeys("aka\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
  Caskk.Disable()
  Caskk.RegisterInputScheme('lifecycle', {k: 'n'}, {a: 'a'})
  Caskk.Enable('lifecycle')
  feedkeys("aka\<Esc>", 'xt')
  assert.equals(getline(1), '前かな後')
  Caskk.Disable()
}

suite.enable_state_is_buffer_local_and_wipeout_releases_it = (): void => {
  const first = Setup()
  defer Cleanup(first)
  Caskk.Enable('lifecycle')
  const second = Setup()
  try
    assert.equals(Caskk.IsEnabled(), false)
    Caskk.Enable('lifecycle')
    Caskk.Disable()
    execute 'noautocmd keepalt hide buffer ' .. first[1]
    assert.equals(Caskk.IsEnabled(), true)
    feedkeys("aka\<Esc>", 'xt')
    assert.equals(getline(1), '前か後')
  finally
    Cleanup(second)
  endtry
  execute 'silent! bwipeout! ' .. first[1]
  assert.equals(Caskk.IsEnabled(), false)
  Caskk.Disable()
}

suite.unknown_scheme_preserves_existing_enable_state_and_mappings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Enable('lifecycle')
  const before = maparg('k', 'i', false, true)
  var caught = ''
  try
    Caskk.Enable('lifecycle-missing')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: unknown input scheme: lifecycle-missing')
  assert.equals(Caskk.IsEnabled(), true)
  assert.equals(maparg('k', 'i', false, true), before)
  feedkeys("aka\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
  Caskk.Disable()
}

suite.failed_enable_restores_mappings_and_allows_retry = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.RegisterInputScheme('lifecycle-duplicate', {}, {}, [
    scheme.SpecialDefinition.new([' '], '空'),
    scheme.SpecialDefinition.new(['<Space>'], '間'),
  ])
  inoremap <buffer> <Space> 旧
  var caught = ''
  try
    Caskk.Enable('lifecycle-duplicate')
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: duplicate physical mapping:'), 0)
  assert.equals(Caskk.IsEnabled(), false)
  assert.equals(maparg('<Space>', 'i'), '旧')
  assert.equals(maparg('k', 'i'), '')
  Caskk.Enable('lifecycle')
  assert.equals(Caskk.IsEnabled(), true)
  Caskk.Disable()
  assert.equals(maparg('<Space>', 'i'), '旧')
}
