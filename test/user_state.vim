vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('user candidate state')
const assert = themis#helper('assert')

def Candidates(): list<dictionary.Candidate>
  return [dictionary.Candidate.new('行', ['移動']), dictionary.Candidate.new('往', []), dictionary.Candidate.new('逝', [])]
enddef

def Texts(candidates: list<dictionary.Candidate>): list<string>
  final texts: list<string> = []
  for candidate in candidates
    texts->add(candidate.text)
  endfor
  return texts
enddef

suite.learning_moves_the_last_used_normal_candidate_to_the_front = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('い', 'く')
  assert.equals(Texts(state.Rank(query, Candidates())), ['行', '往', '逝'])
  state.Learn(query, '逝')
  state.Learn(query, '往')
  state.Learn(query, '逝')
  assert.equals(Texts(state.Rank(query, Candidates())), ['逝', '往', '行'])
}

suite.learning_is_scoped_to_reading_and_first_okuri_character = (): void => {
  const state = user_state.State.new()
  state.Learn(lookup.CreateQuery('い', 'くらい'), '逝')
  assert.equals(Texts(state.Rank(lookup.CreateQuery('い', 'くれば'), Candidates())), ['逝', '行', '往'])
  for query in [lookup.CreateQuery('い', 'こない'), lookup.CreateQuery('い', ''), lookup.CreateQuery('ゆ', 'く'), lookup.CreateQuery('いく', '')]
    assert.equals(Texts(state.Rank(query, Candidates())), ['行', '往', '逝'])
  endfor
}

suite.pin_replacement_returns_the_previous_pin_to_normal = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('い', 'く')
  state.Pin(query, '往')
  state.Learn(query, '逝')
  assert.equals(Texts(state.Rank(query, Candidates())), ['往', '逝', '行'])
  state.Pin(query, '行')
  assert.equals(Texts(state.Rank(query, Candidates())), ['行', '逝', '往'])
}

suite.learning_pinned_or_demoted_candidates_does_not_update_mru = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('い', 'く')
  state.Pin(query, '往')
  state.Demote(query, '逝')
  state.Learn(query, '往')
  state.Learn(query, '逝')
  assert.equals(Texts(state.Rank(query, Candidates())), ['往', '行', '逝'])
  # Replacing the pin reveals whether learning modified its NORMAL history.
  state.Pin(query, '逝')
  assert.equals(Texts(state.Rank(query, Candidates())), ['逝', '行', '往'])
  state.Pin(query, '行')
  assert.equals(Texts(state.Rank(query, Candidates())), ['行', '往', '逝'])
}

suite.explicit_pin_and_demote_replace_each_other = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('い', 'く')
  state.Pin(query, '往')
  state.Demote(query, '往')
  state.Demote(query, '往')
  assert.equals(Texts(state.Rank(query, Candidates())), ['行', '逝', '往'])
  state.Pin(query, '往')
  assert.equals(Texts(state.Rank(query, Candidates())), ['往', '行', '逝'])
}

suite.explicit_choices_are_scoped_to_the_exact_identity = (): void => {
  const state = user_state.State.new()
  state.Pin(lookup.CreateQuery('い', 'くらい'), '往')
  state.Demote(lookup.CreateQuery('い', 'くらい'), '行')
  assert.equals(Texts(state.Rank(lookup.CreateQuery('い', 'くれば'), Candidates())), ['往', '逝', '行'])
  assert.equals(Texts(state.Rank(lookup.CreateQuery('い', 'こない'), Candidates())), ['行', '往', '逝'])
}

suite.state_instances_and_returned_lists_are_independent = (): void => {
  const first = user_state.State.new()
  const second = user_state.State.new()
  const query = lookup.CreateQuery('い', 'く')
  final candidates = Candidates()
  first.Learn(query, '逝')
  var ranked = first.Rank(query, candidates)
  assert.equals(ranked[1].annotations, ['移動'])
  remove(ranked, 0)
  assert.equals(Texts(first.Rank(query, candidates)), ['逝', '行', '往'])
  assert.equals(Texts(second.Rank(query, candidates)), ['行', '往', '逝'])
  assert.equals(Texts(candidates), ['行', '往', '逝'])
}
