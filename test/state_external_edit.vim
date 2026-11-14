vim9script
import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state/runtime.vim' as runtime
import autoload 'caskk/user_state.vim' as state
import autoload 'caskk/user_state/store.vim' as store
import autoload 'caskk/dictionary/lookup.vim' as lookup
final suite = themis#suite('editing active state files')
const assert = themis#helper('assert')

def Restore(snapshot: state.Snapshot)
  runtime.Get().Restore(snapshot)
enddef

suite.manual_changes_win_over_automatic_saves = (): void => {
  const before = runtime.Get().GetSnapshot()
  defer Restore(before)
  for on_exit in [false, true]
    const path = tempname()
    defer delete(path)
    store.Save(path, state.State.new().GetSnapshot())
    runtime.Load(path)
    const edited = state.State.new()
    edited.Pin(lookup.CreateQuery('か', ''), '科')
    store.Save(path, edited.GetSnapshot())
    const bytes = readblob(path)
    runtime.Get().Learn(lookup.CreateQuery('か', ''), '蚊')
    if on_exit
      runtime.SaveAutomatic(path)
    else
      assert.equals(runtime.SaveAutomaticIfChanged(path), '')
    endif
    assert.equals(readblob(path), bytes)
    assert.equals(runtime.Get().GetCandidateTier(lookup.CreateQuery('か', ''), '科'), 'pinned')
    runtime.Get().Learn(lookup.CreateQuery('べつ', ''), '別')
    runtime.SaveAutomatic(path)
    assert.equals(store.Load(path).mru[json_encode(['べつ', ''])], ['別'])
  endfor
}

suite.invalid_manual_edit_is_not_overwritten = (): void => {
  const before = runtime.Get().GetSnapshot()
  defer Restore(before)
  const path = tempname()
  defer delete(path)
  store.Save(path, state.State.new().GetSnapshot())
  runtime.Load(path)
  runtime.Get().Learn(lookup.CreateQuery('か', ''), '蚊')
  writefile(['broken'], path)
  assert.equals(runtime.SaveAutomaticIfChanged(path) != '', true)
  assert.equals(runtime.Get().GetSnapshot().mru[json_encode(['か', ''])], ['蚊'])
  runtime.SaveAutomatic(path)
  assert.equals(readfile(path), ['broken'])
}

suite.writing_the_configured_buffer_reloads_state_immediately = (): void => {
  const before = runtime.Get().GetSnapshot()
  defer Restore(before)
  const path = tempname()
  defer delete(path)
  store.Save(path, state.State.new().GetSnapshot())
  Caskk.Config({state_path: path, state_auto: true})
  runtime.Load(path)
  const previous = bufnr('%')
  execute 'split ' .. fnameescape(path)
  const buffer = bufnr('%')
  try
    setline(2, '["pin","か","","科"]')
    write
    assert.equals(runtime.Get().GetCandidateTier(lookup.CreateQuery('か', ''), '科'), 'pinned')
    setline(2, 'broken')
    write
    assert.equals(runtime.Get().GetCandidateTier(lookup.CreateQuery('か', ''), '科'), 'pinned')
    runtime.SaveAutomatic(path)
    assert.equals(readfile(path)[1], 'broken')
    setline(2, '["pin","か","","蚊"]')
    write
    assert.equals(runtime.Get().GetCandidateTier(lookup.CreateQuery('か', ''), '蚊'), 'pinned')
  finally
    execute 'bwipeout! ' .. buffer
    execute 'buffer ' .. previous
    Caskk.Config({})
  endtry
}
