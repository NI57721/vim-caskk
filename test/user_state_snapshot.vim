vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('user state snapshot')
const assert = themis#helper('assert')

def Texts(candidates: list<dictionary.Candidate>): list<string>
  final texts: list<string> = []
  for candidate in candidates
    texts->add(candidate.text)
  endfor
  return texts
enddef

suite.empty_snapshot_has_a_schema_version_and_clears_existing_state = (): void => {
  const empty = user_state.State.new().GetSnapshot()
  assert.equals(empty.version, 2)
  assert.equals(empty.entries, {})
  assert.equals(empty.mru, {})
  assert.equals(empty.pinned, {})
  assert.equals(empty.demoted, {})
  const state = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  state.AddEntry(query, dictionary.Candidate.new('幹事', []))
  state.Learn(query, '感じ')
  state.Pin(query, '漢字')
  state.Demote(query, '感じ')
  state.Restore(empty)
  const snapshot = state.GetSnapshot()
  assert.equals(snapshot.entries, {})
  assert.equals(snapshot.mru, {})
  assert.equals(snapshot.pinned, {})
  assert.equals(snapshot.demoted, {})
}

suite.restore_preserves_entries_annotations_mru_and_explicit_choices = (): void => {
  const source = user_state.State.new()
  const query = lookup.CreateQuery('い', 'くらい')
  source.AddEntry(query, dictionary.Candidate.new('行', ['移動']))
  source.AddEntry(query, dictionary.Candidate.new('往', []))
  source.AddEntry(query, dictionary.Candidate.new('逝', []))
  source.Learn(query, '逝')
  source.Pin(query, '往')
  source.Demote(query, '行')
  const restored = user_state.State.new()
  restored.Restore(source.GetSnapshot())
  const equivalent = lookup.CreateQuery('い', 'くれば')
  const ranked = restored.Rank(equivalent, [])
  assert.equals(Texts(ranked), ['往', '逝', '行'])
  assert.equals(ranked[2].annotations, ['移動'])
  restored.Reset(equivalent, '往')
  restored.Reset(equivalent, '行')
  assert.equals(Texts(restored.Rank(equivalent, [])), ['逝', '行', '往'])
  assert.equals(Texts(restored.Rank(lookup.CreateQuery('い', 'こない'), [])), ['行', '往', '逝'])
  assert.equals(restored.Rank(lookup.CreateQuery('いく', ''), []), [])
}

suite.snapshot_and_restored_instances_are_independent = (): void => {
  const source = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  source.AddEntry(query, dictionary.Candidate.new('漢字', ['文字']))
  source.AddEntry(query, dictionary.Candidate.new('感じ', []))
  source.Learn(query, '感じ')
  source.Pin(query, '漢字')
  source.Demote(query, '感じ')
  const snapshot = source.GetSnapshot()
  source.DeleteEntry(query, '漢字')
  source.Reset(query, '漢字')
  source.Reset(query, '感じ')
  const first = user_state.State.new()
  const second = user_state.State.new()
  first.Restore(snapshot)
  second.Restore(snapshot)
  first.DeleteEntry(query, '漢字')
  first.Reset(query, '感じ')
  first.AddEntry(query, dictionary.Candidate.new('幹事', []))
  first.Learn(query, '幹事')
  assert.equals(Texts(second.Rank(query, [])), ['漢字', '感じ'])
  assert.equals(second.Rank(query, [])[0].annotations, ['文字'])
  const again = user_state.State.new()
  again.Restore(snapshot)
  assert.equals(Texts(again.Rank(query, [])), ['漢字', '感じ'])
}

suite.unsupported_schema_version_is_rejected_without_changing_state = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  state.AddEntry(query, dictionary.Candidate.new('漢字', []))
  state.Learn(query, '感じ')
  state.Pin(query, '漢字')
  state.Demote(query, '幹事')
  const before = state.GetSnapshot()
  for version in [0, 99]
    var caught = ''
    try
      state.Restore(user_state.Snapshot.new(version, {}, {}, {}, {}))
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: unsupported user state schema version: ' .. version)
    assert.equals(Texts(state.Rank(query, [])), ['漢字'])
    const after = state.GetSnapshot()
    assert.equals(after.mru, before.mru)
    assert.equals(after.pinned, before.pinned)
    assert.equals(after.demoted, before.demoted)
  endfor
}
