vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec
import autoload 'caskk/user_state/store.vim' as store

final suite = themis#suite('user state store')
const assert = themis#helper('assert')

suite.saved_utf8_state_restores_entries_and_all_preferences = (): void => {
  const directory = tempname()
  defer delete(directory, 'rf')
  mkdir(directory)
  const path = directory .. '/state.jsonl'
  const source = user_state.State.new()
  const query = lookup.CreateQuery('い', 'くらい')
  source.AddEntry(query, dictionary.Candidate.new('行', ["移動\t注釈"]))
  source.AddEntry(query, dictionary.Candidate.new('往', []))
  source.AddEntry(query, dictionary.Candidate.new('逝', []))
  source.Learn(query, '逝')
  source.Pin(query, '往')
  source.Demote(query, '行')
  store.Save(path, source.GetSnapshot())
  assert.equals(readdir(directory), ['state.jsonl'])
  assert.equals(getfperm(path), 'rw-------')
  const restored = user_state.State.new()
  restored.Restore(store.Load(path))
  assert.equals(codec.Encode(restored.GetSnapshot()), codec.Encode(source.GetSnapshot()))
  const ranked = restored.Rank(lookup.CreateQuery('い', 'くれば'), [])
  assert.equals(ranked[0].text, '往')
  assert.equals(ranked[1].text, '逝')
  assert.equals(ranked[2].text, '行')
  assert.equals(ranked[2].annotations, ["移動\t注釈"])
}

suite.successive_saves_replace_the_whole_file = (): void => {
  const directory = tempname()
  defer delete(directory, 'rf')
  mkdir(directory)
  const path = directory .. '/state.jsonl'
  const source = user_state.State.new()
  source.AddEntry(lookup.CreateQuery('かんじ', ''), dictionary.Candidate.new('漢字', []))
  store.Save(path, source.GetSnapshot())
  store.Save(path, user_state.State.new().GetSnapshot())
  assert.equals(codec.Encode(store.Load(path)), ['["caskk-user-state","1"]'])
  assert.equals(readdir(directory), ['state.jsonl'])
}

suite.failed_loads_include_the_path_and_leave_current_state_unchanged = (): void => {
  const directory = tempname()
  defer delete(directory, 'rf')
  mkdir(directory)
  const path = directory .. '/state.jsonl'
  const state = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  state.AddEntry(query, dictionary.Candidate.new('漢字', ['文字']))
  state.Pin(query, '漢字')
  const before = codec.Encode(state.GetSnapshot())
  # Missing file, a valid prefix followed by corrupt data, and invalid UTF-8.
  for content in [0z, str2blob(['["caskk-user-state","1"]', '["entry","よみ","","字"]', 'broken']), 0zFF]
    if !empty(content)
      writefile(content, path)
    endif
    var caught = ''
    try
      state.Restore(store.Load(path))
    catch
      caught = v:exception
    endtry
    assert.equals(stridx(caught, 'caskk: cannot load user state: ' .. path .. ':'), 0)
    assert.equals(codec.Encode(state.GetSnapshot()), before)
  endfor
  assert.equals(readdir(directory), ['state.jsonl'])
}

suite.invalid_snapshot_does_not_replace_existing_file_or_leave_temporary_files = (): void => {
  const directory = tempname()
  defer delete(directory, 'rf')
  mkdir(directory)
  const path = directory .. '/state.jsonl'
  writefile(['original'], path)
  var caught = ''
  try
    store.Save(path, user_state.Snapshot.new(2, {}, {}, {}, {}))
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: cannot save user state: ' .. path .. ':'), 0)
  assert.equals(readfile(path), ['original'])
  assert.equals(readdir(directory), ['state.jsonl'])
}

suite.rename_failure_preserves_destination_and_cleans_written_temporary_file = (): void => {
  const directory = tempname()
  defer delete(directory, 'rf')
  mkdir(directory)
  const path = directory .. '/state.jsonl'
  mkdir(path)
  writefile(['keep'], path .. '/sentinel')
  var caught = ''
  try
    store.Save(path, user_state.State.new().GetSnapshot())
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: cannot save user state: ' .. path .. ':'), 0)
  assert.equals(readfile(path .. '/sentinel'), ['keep'])
  assert.equals(readdir(path), ['sentinel'])
  assert.equals(readdir(directory), ['state.jsonl'])
}

suite.missing_parent_fails_without_creating_directories = (): void => {
  const directory = tempname()
  defer delete(directory, 'rf')
  mkdir(directory)
  const path = directory .. '/missing/state.jsonl'
  var caught = ''
  try
    store.Save(path, user_state.State.new().GetSnapshot())
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: cannot save user state: ' .. path .. ':'), 0)
  assert.equals(readdir(directory), [])
}
