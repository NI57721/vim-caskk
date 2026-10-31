vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('user entries')
const assert = themis#helper('assert')

def Texts(candidates: list<dictionary.Candidate>): list<string>
  final texts: list<string> = []
  for candidate in candidates
    texts->add(candidate.text)
  endfor
  return texts
enddef

suite.user_entries_follow_system_candidates_in_registration_order = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  state.AddEntry(query, dictionary.Candidate.new('感じ', []))
  state.AddEntry(query, dictionary.Candidate.new('幹事', []))
  assert.equals(Texts(state.Rank(query, [dictionary.Candidate.new('漢字', [])])), ['漢字', '感じ', '幹事'])
  assert.equals(Texts(state.Rank(query, [])), ['感じ', '幹事'])
}

suite.repeated_registration_merges_annotations_without_duplicates = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  state.AddEntry(query, dictionary.Candidate.new('漢字', ['ユーザー', '文字']))
  state.AddEntry(query, dictionary.Candidate.new('漢字', ['追加', 'ユーザー']))
  const candidates = state.Rank(query, [dictionary.Candidate.new('漢字', ['文字'])])
  assert.equals(Texts(candidates), ['漢字'])
  assert.equals(candidates[0].annotations, ['文字', 'ユーザー', '追加'])
}

suite.deletion_removes_only_the_user_source = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  const system = [dictionary.Candidate.new('漢字', ['システム'])]
  state.AddEntry(query, dictionary.Candidate.new('漢字', ['ユーザー']))
  state.AddEntry(query, dictionary.Candidate.new('感じ', []))
  state.DeleteEntry(query, '漢字')
  const candidates = state.Rank(query, system)
  assert.equals(Texts(candidates), ['漢字', '感じ'])
  assert.equals(candidates[0].annotations, ['システム'])
  state.DeleteEntry(query, '感じ')
  state.DeleteEntry(query, '感じ')
  state.DeleteEntry(lookup.CreateQuery('みとうろく', ''), '不在')
  assert.equals(Texts(state.Rank(query, system)), ['漢字'])
  assert.equals(state.Rank(query, []), [])
}

suite.entries_are_scoped_to_reading_and_first_okuri_character = (): void => {
  const state = user_state.State.new()
  state.AddEntry(lookup.CreateQuery('い', 'くらい'), dictionary.Candidate.new('行', []))
  assert.equals(Texts(state.Rank(lookup.CreateQuery('い', 'くれば'), [])), ['行'])
  for query in [lookup.CreateQuery('い', 'こない'), lookup.CreateQuery('いく', ''), lookup.CreateQuery('ゆ', 'く')]
    state.DeleteEntry(query, '行')
    assert.equals(state.Rank(query, []), [])
  endfor
  assert.equals(Texts(state.Rank(lookup.CreateQuery('い', 'く'), [])), ['行'])
  state.DeleteEntry(lookup.CreateQuery('い', 'くれば'), '行')
  assert.equals(state.Rank(lookup.CreateQuery('い', 'くらい'), []), [])
}

suite.user_entries_obey_learning_pin_and_demote = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  const system = [dictionary.Candidate.new('漢字', [])]
  for text in ['感じ', '幹事', '監事']
    state.AddEntry(query, dictionary.Candidate.new(text, []))
  endfor
  state.Learn(query, '幹事')
  assert.equals(Texts(state.Rank(query, system)), ['幹事', '漢字', '感じ', '監事'])
  state.Pin(query, '感じ')
  state.Demote(query, '幹事')
  assert.equals(Texts(state.Rank(query, system)), ['感じ', '漢字', '監事', '幹事'])
  state.DeleteEntry(query, '感じ')
  assert.equals(Texts(state.Rank(query, system)), ['漢字', '監事', '幹事'])
}

suite.registration_and_ranking_preserve_inputs_and_other_state_instances = (): void => {
  const state = user_state.State.new()
  const other = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  const added = dictionary.Candidate.new('漢字', ['ユーザー'])
  const system = [dictionary.Candidate.new('漢字', ['システム'])]
  state.AddEntry(query, added)
  var ranked = state.Rank(query, system)
  assert.equals(ranked[0].annotations, ['システム', 'ユーザー'])
  remove(ranked, 0)
  assert.equals(Texts(state.Rank(query, [])), ['漢字'])
  assert.equals(other.Rank(query, []), [])
  assert.equals(system[0].annotations, ['システム'])
  assert.equals(added.annotations, ['ユーザー'])
}
