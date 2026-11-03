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
  Caskk.RegisterInputScheme('configured', {k: 'k'}, {a: 'a'})
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

suite.sticky_key_and_function_key_action_are_used_by_public_enable = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Config({sticky_key: ';', mappings: {'<F10>': 'Commit'}})
  Caskk.Enable('configured')
  feedkeys("a;ka\<F10>ka\<Esc>", 'xt')
  assert.equals(getline(1), '前かか後')
  normal! u
  assert.equals(getline(1), '前か後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.config_copies_mappings_and_omitted_input_fields_reset_to_defaults = (): void => {
  const context = Setup()
  defer Cleanup(context)
  final mappings = {'<F10>': 'Commit'}
  Caskk.Config({sticky_key: ';', mappings: mappings})
  mappings['<F10>'] = 'PreviousCandidate'
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
  Caskk.Config({sticky_key: ';', mappings: {'<F10>': 'Commit'}})
  Caskk.Enable('configured')
  Caskk.Config({sticky_key: ':', mappings: {'<F11>': 'Commit'}})
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
  Caskk.Config({sticky_key: ';', mappings: {'<F10>': 'Commit'}, highlight: {preedit: {cterm: 'bold'}}})
  const before = hlget('CaskkPreedit')
  for options in [
    {sticky_key: 1}, {sticky_key: []}, {sticky_key: 'two'},
    {sticky_key: '<NotAKey>'}, {mappings: []}, {mappings: {'<F10>': 1}},
    {mappings: {'<F10>': 'MissingAction'}}, {mappings: {'two': 'Commit'}},
    {mappings: {'<NotAKey>': 'Commit'}},
    {mappings: {' ': 'Commit', '<Space>': 'Convert'}},
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
  Caskk.Config({sticky_key: ';', mappings: {'<F10>': 'Commit'}})
  const before = hlget('CaskkPreedit')
  var caught = ''
  try
    Caskk.Config({sticky_key: ':', mappings: {'<F11>': 'Commit'},
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
  Caskk.Config({sticky_key: '<F9>', mappings: {'<CR>': 'Commit'}})
  Caskk.Enable('configured')
  feedkeys("a\<F9>ka\<CR>ka\<Esc>", 'xt')
  assert.equals(getline(1, '$'), ['前かか後'])
}
