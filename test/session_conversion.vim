vim9script

import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('session conversion')
const assert = themis#helper('assert')

suite.cancel_restores_preedit_and_allows_reading_input_to_continue = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  const before = codec.Encode(preferences.GetSnapshot())
  const started = ime.StartConversion(entries, preferences)
  assert.equals(len(started), 1)
  assert.equals(started[0].text, '蚊')
  assert.equals(started[0].in_candidate, true)
  assert.equals(started[0].replace_preedit, true)
  assert.equals(started[0].commit_preedit, false)
  assert.equals(started[0].state.reading, 'か')
  assert.equals(ime.SelectCandidate(1).text, '科')
  const cancelled = ime.CancelConversion()
  assert.equals(cancelled.text, 'か')
  assert.equals(cancelled.in_candidate, false)
  assert.equals(cancelled.replace_preedit, true)
  assert.equals(cancelled.state.in_preedit, true)
  assert.equals(cancelled.state.reading, 'か')
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates() is null_object, true)
  ime.Feed('k')
  ime.Feed('a')
  assert.equals(ime.GetSnapshot().reading, 'かか')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.cancel_preserves_full_okuri_then_normal_input_commits_the_reading = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/往/')]])
  const preferences = user_state.State.new()
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい'),
  ])
  const ime = session.Session.new(compiled, '', entries, preferences)
  ime.Feed('Z')
  const started = ime.Feed('X')
  assert.equals(started[0].text, '行くらい')
  assert.equals(ime.GetCandidates().query.exact_okuri, 'く')
  const cancelled = ime.CancelConversion()
  assert.equals(cancelled.text, 'いくらい')
  assert.equals(cancelled.state.reading, 'い')
  assert.equals(cancelled.state.okuri, 'くらい')
  assert.equals(cancelled.state.okuri_started, true)
  const committed = ime.Feed('k')
  assert.equals(committed[0].text, 'いくらい')
  assert.equals(committed[0].commit_preedit, true)
  const direct = ime.Feed('a')
  assert.equals(direct[0].text, 'か')
  assert.equals(ime.GetSnapshot().in_preedit, false)
  assert.equals(ime.GetSnapshot().reading, '')
  assert.equals(ime.GetSnapshot().okuri, '')
  assert.equals(preferences.GetSnapshot().mru, {})
}

suite.commit_returns_selected_text_learns_and_resets_input_state = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
  ime.Feed('K')
  ime.Feed('a')
  ime.Feed(';')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  ime.StartConversion(entries, preferences)
  const changed = ime.SelectCandidate(1)
  assert.equals(changed.text, '科')
  assert.equals(changed.in_candidate, true)
  assert.equals(changed.replace_preedit, true)
  const committed = ime.Commit()
  assert.equals(len(committed), 1)
  assert.equals(committed[0].text, '科')
  assert.equals(committed[0].commit_preedit, true)
  assert.equals(committed[0].in_candidate, false)
  assert.equals(committed[0].state.in_preedit, false)
  assert.equals(committed[0].state.reading, '')
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates() is null_object, true)
  assert.equals(preferences.GetSnapshot().mru[json_encode(['か', ''])], ['科'])
  assert.equals(ime.Commit(), [])
  ime.Feed('k')
  const direct = ime.Feed('a')
  assert.equals(direct[0].text, 'か')
  assert.equals(direct[0].state.in_preedit, false)
}

suite.pending_special_is_flushed_before_dictionary_lookup = (): void => {
  const ime = session.Session.new(scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['a'], 'か'),
    scheme.SpecialDefinition.new(['a', 'b'], 'かん'),
  ]))
  ime.Feed('A')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  const results = ime.StartConversion(entries, user_state.State.new())
  assert.equals(len(results), 2)
  assert.equals(results[0].state.reading, 'か')
  assert.equals(results[0].in_candidate, false)
  assert.equals(results[1].text, '蚊')
  assert.equals(results[1].in_candidate, true)
  assert.equals(ime.Pending(), [])
}

suite.unhandled_pending_input_does_not_start_candidate_selection = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  for key in ['K', 'a', 'k']
    ime.Feed(key)
  endfor
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  const results = ime.StartConversion(entries, user_state.State.new())
  assert.equals(len(results), 1)
  assert.equals(results[0].unhandled[0].key, 'k')
  assert.equals(results[0].state.reading, 'か')
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates() is null_object, true)
}

suite.no_candidates_preserve_reading_and_expose_the_registration_query = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  assert.equals(ime.StartConversion({}, user_state.State.new()), [])
  ime.Feed('K')
  ime.Feed('a')
  const results = ime.StartConversion({}, user_state.State.new())
  assert.equals(results[0].state.in_preedit, true)
  assert.equals(results[0].state.reading, 'か')
  assert.equals(results[0].in_candidate, false)
  assert.equals(results[0].replace_preedit, false)
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates().query.reading, 'か')
  assert.equals(ime.GetCandidates().candidates, [])
}

suite.active_selection_rejects_restarting_conversion = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  ime.StartConversion(entries, preferences)
  var caught = ''
  try
    ime.StartConversion(entries, preferences)
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: conversion selection is active')
  assert.equals(ime.InCandidate(), true)
  assert.equals(ime.GetSnapshot().reading, 'か')
  assert.equals(ime.Pending(), [])
  assert.equals(ime.SelectCandidate(1).text, '科')
  assert.equals(ime.Commit()[0].text, '科')
}

suite.normal_input_commits_the_selected_candidate_then_keeps_the_new_pending_key = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  ime.StartConversion(entries, preferences)
  ime.SelectCandidate(1)
  const results = ime.Feed('k')
  assert.equals(len(results), 1)
  assert.equals(results[0].text, '科')
  assert.equals(results[0].commit_preedit, true)
  assert.equals(results[0].state.in_preedit, false)
  assert.equals(results[0].in_candidate, false)
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates() is null_object, true)
  assert.equals(ime.Pending()[0].key, 'k')
  assert.equals(preferences.GetSnapshot().mru[json_encode(['か', ''])], ['科'])
  const following = ime.Feed('a')
  assert.equals(len(following), 1)
  assert.equals(following[0].text, 'か')
  assert.equals(following[0].commit_preedit, false)
  assert.equals(following[0].state.in_preedit, false)
}

suite.commit_result_precedes_direct_output_from_the_same_input = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}, [scheme.SpecialDefinition.new(['x'], '。')]))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  ime.StartConversion(entries, user_state.State.new())
  const results = ime.Feed('x')
  assert.equals(len(results), 2)
  assert.equals(results[0].text, '蚊')
  assert.equals(results[0].commit_preedit, true)
  assert.equals(results[1].text, '。')
  assert.equals(results[1].commit_preedit, false)
  assert.equals(results[1].state.in_preedit, false)
}

suite.modified_and_sticky_input_start_a_new_preedit_after_committing = (): void => {
  for keys in [['K', 'a'], [';', 'k', 'a']]
    const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
    ime.Feed('K')
    ime.Feed('a')
    const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
    ime.StartConversion(entries, user_state.State.new())
    const committed = ime.Feed(keys[0])
    assert.equals(len(committed), 1)
    assert.equals(committed[0].text, '蚊')
    assert.equals(committed[0].commit_preedit, true)
    for key in keys[1 :]
      ime.Feed(key)
    endfor
    assert.equals(ime.GetSnapshot().in_preedit, true)
    assert.equals(ime.GetSnapshot().reading, 'か')
    assert.equals(ime.GetSnapshot().okuri, '')
    assert.equals(committed[0].state.in_preedit, false)
    assert.equals(committed[0].state.reading, '')
  endfor
}

suite.unhandled_input_is_returned_after_the_candidate_commit = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  ime.StartConversion(entries, user_state.State.new())
  const results = ime.Feed('?')
  assert.equals(len(results), 2)
  assert.equals(results[0].text, '蚊')
  assert.equals(results[0].commit_preedit, true)
  assert.equals(results[1].text, '')
  assert.equals(results[1].unhandled[0].key, '?')
  assert.equals(results[1].state.in_preedit, false)
}

suite.selection_actions_outside_candidate_state_are_rejected = (): void => {
  const ime = session.Session.new(scheme.Compile({}, {}))
  for action in ['select', 'cancel', 'previous']
    var caught = ''
    try
      if action ==# 'select'
        ime.SelectCandidate(0)
      elseif action ==# 'previous'
        ime.PreviousCandidate()
      else
        ime.CancelConversion()
      endif
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: no active conversion selection')
    assert.equals(ime.GetSnapshot().in_preedit, false)
  endfor
}
