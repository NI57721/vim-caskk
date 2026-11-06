vim9script

import autoload 'caskk/input/mapping_state.vim' as mapping_state

const suite = themis#suite('mapping state ownership')
const assert = themis#helper('assert')

suite.restore_preserves_script_context_and_user_replacements = (): void => {
  enew!
  const state = mapping_state.State.new()
  inoremap <buffer> <F6> <ScriptCmd>len([])<CR>
  const original = maparg('<F6>', 'i', false, true)
  state.Install('<F6>', '<Nop>')
  state.Restore()
  assert.equals(maparg('<F6>', 'i', false, true), original)
  state.Install('<F6>', '<Nop>')
  inoremap <buffer> <F6> replacement
  state.Restore()
  assert.equals(maparg('<F6>', 'i', false, true).rhs, 'replacement')
  bwipeout!
}

suite.temporary_release_and_reinstall_keep_the_original_mapping = (): void => {
  enew!
  const state = mapping_state.State.new()
  inoremap <buffer> <F6> original
  state.Install('<F6>', 'managed')
  state.Release('<F6>')
  assert.equals(maparg('<F6>', 'i', false, true).rhs, 'original')
  state.Reinstall('<F6>', 'managed')
  state.Restore()
  assert.equals(maparg('<F6>', 'i', false, true).rhs, 'original')
  bwipeout!
}
