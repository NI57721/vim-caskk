vim9script

import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/store.vim' as store
import autoload 'caskk/dictionary/lookup.vim' as lookup

final suite = themis#suite('automatic user state lifecycle')
const assert = themis#helper('assert')

class Result
  const status: number
  const output: string

  def new(this.status, this.output)
  enddef
endclass

def Directory(): string
  const directory = tempname()
  mkdir(directory)
  writefile(['か /蚊/科/'], directory .. '/system')
  return directory
enddef

def Run(directory: string, commands: list<string>): Result
  const script = directory .. '/child.vim'
  delete(directory .. '/error')
  writefile([
    'vim9script',
    'execute "set runtimepath^=" .. fnameescape(' .. string(getcwd()) .. ')',
    "import autoload 'caskk.vim' as Caskk",
    'set nomore',
    "Caskk.RegisterInputScheme('automatic', {k: 'k'}, {a: 'a'})",
    'enew',
    'setlocal buftype=nofile noswapfile',
    "setline(1, '前後')",
    'cursor(1, 1)',
    'try',
  ] + commands + [
    'catch',
    '  writefile([v:exception, string(Caskk.IsEnabled())], ' .. string(directory .. '/error') .. ')',
    '  cquit',
    'endtry',
    'qa!',
  ], script)
  var output = system([v:progpath, '-v', '-X', '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-V1', '-S', script])
  const status = v:shell_error
  if filereadable(directory .. '/error')
    output ..= join(readfile(directory .. '/error'), "\n")
  endif
  return Result.new(status, output)
enddef

def Configure(directory: string, path: string = ''): string
  const destination = path == '' ? directory .. '/state.jsonl' : path
  return 'Caskk.Config({state_auto: true, state_path: ' .. string(destination)
    .. ', dictionaries: [' .. string(directory .. '/system')
    .. "], mappings: {s: 'StartConversion', n: 'NextCandidate'}})"
enddef

def Input(keys: string): string
  return 'feedkeys("' .. keys .. '\<Esc>", "xt")'
enddef

suite.first_enable_loads_history_and_real_exit_saves_new_learning = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  const path = directory .. '/state.jsonl'
  const state = user_state.State.new()
  state.Learn(lookup.CreateQuery('か', ''), '科')
  store.Save(path, state.GetSnapshot())
  const result = Run(directory, [Configure(directory), "Caskk.Enable('automatic')", Input('aKasn'),
    'writefile([getline(1)], ' .. string(directory .. '/text') .. ')'])
  assert.equals(result.status, 0, result.output)
  assert.equals(readfile(directory .. '/text'), ['前蚊後'])
  assert.equals(store.Load(path).mru[json_encode(['か', ''])], ['蚊', '科'])
  assert.equals(readdir(directory), ['child.vim', 'state.jsonl', 'system', 'text'])
}

suite.missing_file_is_created_on_exit_after_successful_activation = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  const path = directory .. '/state.jsonl'
  const result = Run(directory, [Configure(directory), "Caskk.Enable('automatic')", Input('aKasn')])
  assert.equals(result.status, 0, result.output)
  assert.equals(store.Load(path).mru[json_encode(['か', ''])], ['科'])
  assert.equals(getfperm(path), 'rw-------')
  assert.equals(readdir(directory), ['child.vim', 'state.jsonl', 'system'])
  const restarted = Run(directory, [Configure(directory), "Caskk.Enable('automatic')", Input('aKas'),
    'writefile([getline(1)], ' .. string(directory .. '/text') .. ')'])
  assert.equals(restarted.status, 0, restarted.output)
  assert.equals(readfile(directory .. '/text'), ['前科後'])
}

suite.reenable_and_reconfigure_same_path_do_not_reload_stale_history = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  store.Save(directory .. '/state.jsonl', user_state.State.new().GetSnapshot())
  const result = Run(directory, [Configure(directory), "Caskk.Enable('automatic')", Input('aKasn'),
    'Caskk.Disable()', Configure(directory), "Caskk.Enable('automatic')", Input('aKas'),
    'writefile([getline(1)], ' .. string(directory .. '/text') .. ')'])
  assert.equals(result.status, 0, result.output)
  assert.equals(readfile(directory .. '/text'), ['前科科後'])
}

suite.corrupt_file_blocks_activation_and_is_not_overwritten_on_exit = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  const path = directory .. '/state.jsonl'
  writefile(['broken'], path)
  const before = readblob(path)
  const result = Run(directory, [Configure(directory), "Caskk.Enable('automatic')"])
  assert.equals(result.status != 0, true)
  const error = readfile(directory .. '/error')
  assert.equals(stridx(error[0], 'caskk: cannot load user state: ' .. path .. ':'), 0)
  assert.equals(error[1], 'false')
  assert.equals(readblob(path), before)
  assert.equals(readdir(directory), ['child.vim', 'error', 'state.jsonl', 'system'])
}

suite.unused_automatic_configuration_does_not_create_a_state_file = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  const result = Run(directory, [Configure(directory)])
  assert.equals(result.status, 0, result.output)
  assert.equals(readdir(directory), ['child.vim', 'system'])
}

suite.omitted_automatic_setting_disables_exit_saving_after_reconfiguration = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  const result = Run(directory, [Configure(directory), "Caskk.Enable('automatic')", Input('aKasn'),
    'Caskk.Config({state_path: ' .. string(directory .. '/state.jsonl') .. '})'])
  assert.equals(result.status, 0, result.output)
  assert.equals(readdir(directory), ['child.vim', 'system'])
}

suite.exit_save_failure_is_reported_without_creating_parent_directories = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  const path = directory .. '/missing/state.jsonl'
  const result = Run(directory, [Configure(directory, path), "Caskk.Enable('automatic')", Input('aKasn'),
    'writefile([getline(1)], ' .. string(directory .. '/text') .. ')'])
  assert.equals(stridx(result.output, 'caskk: cannot save user state: ' .. path .. ':') >= 0, true, result.output)
  assert.equals(readfile(directory .. '/text'), ['前科後'])
  assert.equals(readdir(directory), ['child.vim', 'system', 'text'])
}

suite.failed_mapping_installation_does_not_initialize_or_save_state = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  const result = Run(directory, [Configure(directory),
    "Caskk.RegisterInputScheme('duplicate', {' ': 'k'}, {'<Space>': 'a'})",
    "Caskk.Enable('duplicate')"])
  assert.equals(result.status != 0, true)
  const error = readfile(directory .. '/error')
  assert.equals(stridx(error[0], 'caskk: duplicate physical mapping:'), 0)
  assert.equals(error[1], 'false')
  assert.equals(readdir(directory), ['child.vim', 'error', 'system'])
}

suite.failed_explicit_reload_disarms_automatic_save_for_that_path = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  const path = directory .. '/state.jsonl'
  store.Save(path, user_state.State.new().GetSnapshot())
  const result = Run(directory, [Configure(directory), "Caskk.Enable('automatic')", Input('aKasn'),
    "writefile(['broken'], " .. string(path) .. ')', 'Caskk.LoadState()'])
  assert.equals(result.status != 0, true)
  const error = readfile(directory .. '/error')
  assert.equals(stridx(error[0], 'caskk: cannot load user state: ' .. path .. ':'), 0)
  assert.equals(error[1], 'true')
  assert.equals(readfile(path), ['broken'])
}

suite.relative_state_path_stays_bound_to_configuration_directory_until_exit = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  mkdir(directory .. '/elsewhere')
  const result = Run(directory, [
    'execute "lcd " .. fnameescape(' .. string(directory) .. ')',
    Configure(directory, 'state.jsonl'), "Caskk.Enable('automatic')", Input('aKasn'),
    'execute "lcd " .. fnameescape(' .. string(directory .. '/elsewhere') .. ')',
  ])
  assert.equals(result.status, 0, result.output)
  assert.equals(readdir(directory), ['child.vim', 'elsewhere', 'state.jsonl', 'system'])
  assert.equals(readdir(directory .. '/elsewhere'), [])
  assert.equals(store.Load(directory .. '/state.jsonl').mru[json_encode(['か', ''])], ['科'])
}

suite.invalid_automatic_settings_are_rejected_before_activation = (): void => {
  const directory = Directory()
  defer delete(directory, 'rf')
  for [options, expected] in [
    ["{state_auto: 1}", 'state_auto must be a bool'],
    ["{state_auto: 'yes'}", 'state_auto must be a bool'],
    ['{state_auto: true}', 'state_auto requires a nonempty state_path'],
  ]
    const result = Run(directory, ['Caskk.Config(' .. options .. ')'])
    assert.equals(result.status != 0, true)
    const error = readfile(directory .. '/error')
    assert.equals(error[0], 'caskk: invalid configuration: ' .. expected)
    assert.equals(error[1], 'false')
  endfor
  assert.equals(readdir(directory), ['child.vim', 'error', 'system'])
}
