vim9script

import autoload 'caskk.vim' as Caskk
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/user_state/codec.vim' as codec
import autoload 'caskk/user_state/store.vim' as store

final suite = themis#suite('public user state persistence')
const assert = themis#helper('assert')

class Fixture
  const previous: number
  const buffer: number
  const directory: string
  const snapshot: user_state.Snapshot

  def new(this.previous, this.buffer, this.directory, this.snapshot)
  enddef
endclass

def Setup(): Fixture
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  const directory = tempname()
  mkdir(directory)
  writefile(['か /蚊/科/'], directory .. '/system')
  const snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  Caskk.Config({})
  Caskk.RegisterInputScheme({name: 'persistence', consonants: {k: 'k'}, combinations: {a: 'a'}})
  return Fixture.new(previous, number, directory, snapshot)
enddef

def Cleanup(fixture: Fixture)
  try
    Caskk.Disable()
    Caskk.Config({})
  finally
    user_runtime.Get().Restore(fixture.snapshot)
    execute 'noautocmd keepalt hide buffer ' .. fixture.previous
    execute 'silent! bwipeout! ' .. fixture.buffer
    delete(fixture.directory, 'rf')
  endtry
enddef

def SaveCurrent()
  Caskk.SaveState()
enddef

suite.round_trip_preserves_entries_annotations_mru_pin_and_demotion = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const path = fixture.directory .. '/state.jsonl'
  Caskk.Config({state_path: path, dictionaries: [fixture.directory .. '/system'],
    mappings: {s: 'Convert'}})
  const query = lookup.CreateQuery('か', '')
  const state = user_runtime.Get()
  state.AddEntry(query, dictionary.Candidate.new('課', ['ユーザー登録']))
  state.Learn(query, '科')
  state.Pin(query, '課')
  state.Demote(query, '蚊')
  const before = codec.Encode(state.GetSnapshot())
  Caskk.SaveState()
  assert.equals(getfperm(path), 'rw-------')
  assert.equals(readdir(fixture.directory), ['state.jsonl', 'system'])
  state.Restore(user_state.State.new().GetSnapshot())
  Caskk.LoadState()
  assert.equals(codec.Encode(state.GetSnapshot()), before)
  Caskk.Enable('persistence')
  feedkeys("aKas\<Esc>", 'xt')
  assert.equals(getline(1), '前課後')
}

suite.loaded_learning_is_used_by_an_already_enabled_buffer = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const path = fixture.directory .. '/state.jsonl'
  Caskk.Config({state_path: path, dictionaries: [fixture.directory .. '/system'],
    mappings: {s: 'Convert', n: 'NextCandidate'}})
  Caskk.Enable('persistence')
  feedkeys("aKasn\<Esc>", 'xt')
  assert.equals(getline(1), '前科後')
  Caskk.SaveState()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  Caskk.LoadState()
  feedkeys("aKas\<Esc>", 'xt')
  assert.equals(getline(1), '前科科後')
}

suite.failed_loads_preserve_current_shared_state = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const path = fixture.directory .. '/state.jsonl'
  Caskk.Config({state_path: path})
  user_runtime.Get().Learn(lookup.CreateQuery('か', ''), '科')
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  for bytes in [0z, str2blob(['["caskk-user-state","1"]', '["entry","か","","課"]', 'broken']), 0zFF]
    if !empty(bytes)
      writefile(bytes, path)
    endif
    var caught = ''
    try
      Caskk.LoadState()
    catch
      caught = v:exception
    endtry
    assert.equals(stridx(caught, 'caskk: cannot load user state: ' .. path .. ':'), 0)
    assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
  endfor
}

suite.failed_save_preserves_destination_memory_and_cleans_temporary_files = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const path = fixture.directory .. '/blocked'
  mkdir(path)
  writefile(['keep'], path .. '/sentinel')
  Caskk.Config({state_path: path})
  user_runtime.Get().Learn(lookup.CreateQuery('か', ''), '科')
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  var caught = ''
  try
    Caskk.SaveState()
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: cannot save user state: ' .. fnamemodify(path, ':p') .. ':'), 0)
  assert.equals(readfile(path .. '/sentinel'), ['keep'])
  assert.equals(readdir(path), ['sentinel'])
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
  assert.equals(readdir(fixture.directory), ['blocked', 'system'])
}

suite.unconfigured_path_rejects_load_and_save_without_changing_state = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  user_runtime.Get().Learn(lookup.CreateQuery('か', ''), '科')
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  for Operation in [Caskk.LoadState, Caskk.SaveState]
    var caught = ''
    try
      Operation()
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: user state path is not configured')
    assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
  endfor
  assert.equals(readdir(fixture.directory), ['system'])
}

suite.invalid_configuration_keeps_previous_state_path = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const path = fixture.directory .. '/state.jsonl'
  const rejected = fixture.directory .. '/rejected.jsonl'
  Caskk.Config({state_path: path})
  for options in [{state_path: 1}, {state_path: []}, {state_path: {}},
    {state_path: rejected, highlight: {preedit: {ctermfg: 'caskk-invalid-color'}}}]
    var caught = ''
    try
      Caskk.Config(options)
    catch
      caught = v:exception
    endtry
    assert.equals(stridx(caught, 'caskk: invalid configuration:'), 0)
  endfor
  Caskk.SaveState()
  assert.equals(filereadable(path), 1)
  assert.equals(readdir(fixture.directory), ['state.jsonl', 'system'])
}

suite.configuring_a_path_does_not_implicitly_load_or_save_and_omission_resets_it = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const path = fixture.directory .. '/state.jsonl'
  store.Save(path, user_state.State.new().GetSnapshot())
  const original = readblob(path)
  user_runtime.Get().Learn(lookup.CreateQuery('か', ''), '科')
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  Caskk.Config({state_path: path})
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
  assert.equals(readblob(path), original)
  Caskk.Config({})
  var caught = ''
  try
    Caskk.SaveState()
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: user state path is not configured')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
  assert.equals(readblob(path), original)
}

suite.save_during_selection_does_not_commit_the_candidate = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const path = fixture.directory .. '/state.jsonl'
  Caskk.Config({state_path: path, dictionaries: [fixture.directory .. '/system'],
    mappings: {s: 'Convert', n: 'NextCandidate'}})
  inoremap <buffer> <F12> <ScriptCmd>SaveCurrent()<CR>
  Caskk.Enable('persistence')
  feedkeys("aKasn\<F12>\<Esc>", 'xt')
  assert.equals(getline(1), '前科後')
  assert.equals(store.Load(path).mru, {})
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['か', ''])], ['科'])
}
