vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('session registration completion')
const assert = themis#helper('assert')

suite.cancel_registration_keeps_preedit_and_preferences_without_registering = (): void => {
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  ime.StartConversion({}, preferences)
  const before = codec.Encode(preferences.GetSnapshot())
  const result = ime.CancelRegistration()
  assert.equals(result.text, 'か')
  assert.equals(result.replace_preedit, true)
  assert.equals(result.commit_preedit, false)
  assert.equals(result.registration_requested, false)
  assert.equals(result.in_candidate, false)
  assert.equals(result.state.in_preedit, true)
  assert.equals(result.state.reading, 'か')
  assert.equals(ime.GetCandidates() is null_object, true)
  ime.Feed('k')
  ime.Feed('a')
  assert.equals(ime.GetSnapshot().reading, 'かか')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.cancel_registration_after_exhaustion_keeps_okuri_for_plain_commit = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const preferences = user_state.State.new()
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい')])
  const ime = session.Session.new(compiled, '', entries, preferences)
  ime.Feed('Z')
  ime.Feed('X')
  ime.NextCandidate()
  const before = codec.Encode(preferences.GetSnapshot())
  const result = ime.CancelRegistration()
  assert.equals(result.text, 'いくらい')
  assert.equals(result.state.reading, 'い')
  assert.equals(result.state.okuri, 'くらい')
  assert.equals(result.state.okuri_started, true)
  assert.equals(ime.InCandidate(), false)
  const committed = ime.Feed('k')
  assert.equals(committed[0].text, 'いくらい')
  assert.equals(committed[0].commit_preedit, true)
  assert.equals(ime.Feed('a')[0].text, 'か')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  assert.equals(entries['いk'].candidates[0].text, '行')
}

suite.registration_can_be_requested_again_after_cancellation = (): void => {
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  ime.StartConversion({}, preferences)
  ime.CancelRegistration()
  var caught = ''
  try
    ime.CancelRegistration()
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: no current dictionary registration request')
  assert.equals(ime.StartConversion({}, preferences)[0].registration_requested, true)
  assert.equals(ime.Register(dictionary.Candidate.new('蚊', [])).text, '蚊')
  assert.equals(preferences.GetSnapshot().entries[json_encode(['か', ''])][0].text, '蚊')
}

suite.registration_adds_and_learns_the_candidate_then_replaces_and_commits_preedit = (): void => {
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
  ime.Feed('K')
  ime.Feed('a')
  assert.equals(ime.StartConversion({}, preferences)[0].registration_requested, true)
  const result = ime.Register(dictionary.Candidate.new('蚊', ['虫']))
  assert.equals(result.text, '蚊')
  assert.equals(result.replace_preedit, true)
  assert.equals(result.commit_preedit, true)
  assert.equals(result.registration_requested, false)
  assert.equals(result.in_candidate, false)
  assert.equals(result.state.in_preedit, false)
  assert.equals(result.state.reading, '')
  assert.equals(ime.GetCandidates() is null_object, true)
  const key = json_encode(['か', ''])
  const snapshot = preferences.GetSnapshot()
  assert.equals(snapshot.entries[key][0].text, '蚊')
  assert.equals(snapshot.entries[key][0].annotations, ['虫'])
  assert.equals(snapshot.mru[key], ['蚊'])
  ime.Feed('k')
  assert.equals(ime.Feed('a')[0].text, 'か')
}

suite.registering_the_same_hiragana_as_the_reading_commits_without_learning_or_adding_it = (): void => {
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';', {}, preferences)
  ime.Feed('K')
  ime.Feed('a')
  assert.equals(ime.StartConversion({}, preferences)[0].registration_requested, true)
  const result = ime.Register(dictionary.Candidate.new('か', []))
  assert.equals(result.text, 'か')
  assert.equals(result.replace_preedit, true)
  assert.equals(result.commit_preedit, true)
  assert.equals(preferences.GetSnapshot().entries, {})
  assert.equals(preferences.GetSnapshot().mru, {})
}

suite.registration_preserves_full_okuri_but_stores_only_the_candidate_body = (): void => {
  const preferences = user_state.State.new()
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい')])
  const ime = session.Session.new(compiled, '', {}, preferences)
  ime.Feed('Z')
  assert.equals(ime.Feed('X')[0].registration_requested, true)
  const result = ime.Register(dictionary.Candidate.new('行', []))
  assert.equals(result.text, '行くらい')
  assert.equals(result.state.okuri, '')
  assert.equals(result.state.okuri_started, false)
  const key = json_encode(['い', 'く'])
  assert.equals(preferences.GetSnapshot().entries[key][0].text, '行')
  assert.equals(preferences.GetSnapshot().mru[key], ['行'])
  assert.equals(conversion.Prepare({}, preferences, 'い', 'くれば').TextAt(0), '行くれば')
  assert.equals(conversion.Prepare({}, preferences, 'い', 'こない').TextAt(0), '行こない')
}

suite.registration_after_exhaustion_keeps_system_candidates_and_ranks_the_new_entry_first = (): void => {
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  ime.StartConversion(entries, preferences)
  ime.NextCandidate()
  assert.equals(ime.NextCandidate().registration_requested, true)
  assert.equals(ime.Register(dictionary.Candidate.new('課', [])).text, '課')
  const prepared = conversion.Prepare(entries, preferences, 'か')
  assert.equals(len(prepared.candidates), 3)
  assert.equals(prepared.TextAt(0), '課')
  assert.equals(prepared.TextAt(1), '蚊')
  assert.equals(prepared.TextAt(2), '科')
  assert.equals(entries['か'].candidates[0].text, '蚊')
  assert.equals(entries['か'].candidates[1].text, '科')
}

suite.empty_registration_is_rejected_without_consuming_the_request = (): void => {
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  ime.StartConversion({}, preferences)
  var caught = ''
  try
    ime.Register(dictionary.Candidate.new('', []))
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: registered candidate text must not be empty')
  assert.equals(codec.Encode(preferences.GetSnapshot()), ['["caskk-user-state","2"]'])
  assert.equals(ime.GetSnapshot().reading, 'か')
  assert.equals(ime.Register(dictionary.Candidate.new('蚊', [])).text, '蚊')
}

suite.registration_requires_a_current_request_and_cannot_be_applied_twice = (): void => {
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  for phase in ['direct', 'candidate', 'cancelled', 'completed', 'edited', 'registration_cancelled']
    const preferences = user_state.State.new()
    const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
    if phase !=# 'direct'
      ime.Feed('K')
      ime.Feed('a')
      if phase ==# 'candidate' || phase ==# 'cancelled'
        ime.StartConversion(entries, preferences)
        if phase ==# 'cancelled'
          ime.CancelConversion()
        endif
      else
        ime.StartConversion({}, preferences)
        if phase ==# 'completed'
          ime.Register(dictionary.Candidate.new('科', []))
        elseif phase ==# 'registration_cancelled'
          ime.CancelRegistration()
        else
          ime.Feed('k')
        endif
      endif
    endif
    const before = codec.Encode(preferences.GetSnapshot())
    const reading = ime.GetSnapshot().reading
    var caught = ''
    try
      ime.Register(dictionary.Candidate.new('課', []))
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: no current dictionary registration request')
    assert.equals(codec.Encode(preferences.GetSnapshot()), before)
    assert.equals(ime.GetSnapshot().reading, reading)
    caught = ''
    try
      ime.CancelRegistration()
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: no current dictionary registration request')
    assert.equals(codec.Encode(preferences.GetSnapshot()), before)
    assert.equals(ime.GetSnapshot().reading, reading)
  endfor
}

suite.same_reading_with_annotation_is_registered = (): void => {
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({}, {}), '', {}, preferences, 'か')
  ime.StartConversion({}, preferences)
  ime.Register(dictionary.Candidate.new('か', ['説明']))
  assert.equals(preferences.GetSnapshot().entries[json_encode(['か', ''])][0].annotations, ['説明'])
}
