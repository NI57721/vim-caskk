vim9script

import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('selected candidate information')
const assert = themis#helper('assert')

suite.information_tracks_selection_without_mutating_previous_information_or_learning = (): void => {
  const entries = merger.Merge([[parser.ParseLine('か /蚊;昆虫/科;学科/')]])
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({}, {}), '', entries, preferences, 'か')
  const before = codec.Encode(preferences.GetSnapshot())
  ime.StartConversion(entries, preferences)
  const first = ime.GetCandidatesInfo().candidates[ime.GetCandidatesInfo().selected_index]
  assert.equals(first.index, 0)
  assert.equals(first.count, 2)
  assert.equals(first.text, '蚊')
  assert.equals(first.annotations, ['昆虫'])
  ime.NextCandidate()
  const second = ime.GetCandidatesInfo().candidates[ime.GetCandidatesInfo().selected_index]
  assert.equals(second.index, 1)
  assert.equals(second.count, 2)
  assert.equals(second.text, '科')
  assert.equals(second.annotations, ['学科'])
  assert.equals(first.text, '蚊')
  assert.equals(first.index, 0)
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.information_includes_display_okuri_and_preserves_the_dictionary_body = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行;移動/往;前進/')]])
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {u: 'u'}), '', entries, null_object, 'い')
  ime.Feed('K')
  ime.Feed('u')
  assert.equals(ime.GetCandidatesInfo().candidates[ime.GetCandidatesInfo().selected_index].text, '行く')
  assert.equals(ime.GetCandidatesInfo().candidates[ime.GetCandidatesInfo().selected_index].annotations, ['移動'])
  ime.NextCandidate()
  assert.equals(ime.GetCandidatesInfo().candidates[ime.GetCandidatesInfo().selected_index].text, '往く')
  assert.equals(ime.GetCandidatesInfo().candidates[ime.GetCandidatesInfo().selected_index].annotations, ['前進'])
  assert.equals(entries['いk'].candidates[0].text, '行')
}

suite.information_is_absent_outside_active_candidate_selection = (): void => {
  const preferences = user_state.State.new()
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  assert.equals(ime.GetCandidatesInfo() is null_object, true)
  ime.Feed('K')
  ime.Feed('a')
  assert.equals(ime.GetCandidatesInfo() is null_object, true)
  ime.StartConversion({}, preferences)
  assert.equals(ime.GetCandidatesInfo() is null_object, true)
  ime.CancelRegistration()
  ime.StartConversion(entries, preferences)
  assert.equals(ime.GetCandidatesInfo().candidates[ime.GetCandidatesInfo().selected_index].text, '蚊')
  ime.Commit()
  assert.equals(ime.GetCandidatesInfo() is null_object, true)
  ime.Feed('K')
  ime.Feed('a')
  ime.StartConversion(entries, preferences)
  ime.PreviousCandidate()
  assert.equals(ime.GetCandidatesInfo() is null_object, true)
}
