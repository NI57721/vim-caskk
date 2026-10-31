vim9script

import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('automatic okuri conversion')
const assert = themis#helper('assert')

suite.completed_okuri_immediately_displays_the_first_ranked_candidate = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/往/')]])
  const compiled = scheme.Compile({q: '', k: 'k'}, {i: 'i', u: 'u'})
  for keys in [['Q', 'i', 'K', 'u'], [';', 'q', 'i', ';', 'k', 'u']]
    const preferences = user_state.State.new()
    preferences.Pin(lookup.CreateQuery('い', 'く'), '往')
    const ime = session.Session.new(compiled, ';', entries, preferences)
    var results: list<session.Result> = []
    for key in keys
      results = ime.Feed(key)
    endfor
    assert.equals(len(results), 1)
    assert.equals(results[0].text, '往く')
    assert.equals(results[0].in_candidate, true)
    assert.equals(results[0].replace_preedit, true)
    assert.equals(results[0].registration_requested, false)
    assert.equals(results[0].state.reading, 'い')
    assert.equals(results[0].state.okuri, 'く')
    assert.equals(ime.InCandidate(), true)
    assert.equals(preferences.GetSnapshot().mru, {})
  endfor
}

suite.previous_from_the_first_candidate_restores_reading_before_normal_input = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/往/')]])
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({q: '', k: 'k'}, {i: 'i', u: 'u', a: 'a'}), '', entries, preferences)
  for key in ['Q', 'i', 'K', 'u']
    ime.Feed(key)
  endfor
  ime.SelectCandidate(1)
  assert.equals(ime.PreviousCandidate().text, '行く')
  assert.equals(ime.InCandidate(), true)
  const reading = ime.PreviousCandidate()
  assert.equals(reading.text, 'いく')
  assert.equals(reading.in_candidate, false)
  assert.equals(reading.replace_preedit, true)
  assert.equals(reading.state.in_preedit, true)
  const committed = ime.Feed('k')
  assert.equals(committed[0].text, 'いく')
  assert.equals(committed[0].commit_preedit, true)
  assert.equals(ime.Feed('a')[0].text, 'か')
  assert.equals(preferences.GetSnapshot().mru, {})
}

suite.normal_input_commits_the_selected_okuri_candidate_and_learns_its_body = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/往/')]])
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({q: '', k: 'k'}, {i: 'i', u: 'u', a: 'a'}), '', entries, preferences)
  for key in ['Q', 'i', 'K', 'u']
    ime.Feed(key)
  endfor
  ime.SelectCandidate(1)
  const committed = ime.Feed('k')
  assert.equals(committed[0].text, '往く')
  assert.equals(committed[0].commit_preedit, true)
  assert.equals(committed[0].state.in_preedit, false)
  assert.equals(committed[0].state.okuri, '')
  assert.equals(ime.Feed('a')[0].text, 'か')
  assert.equals(preferences.GetSnapshot().mru[json_encode(['い', 'く'])], ['往'])
}

suite.missing_okuri_candidate_immediately_requests_registration = (): void => {
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({q: '', k: 'k'}, {i: 'i', u: 'u'}), '', {}, preferences)
  var results: list<session.Result> = []
  for key in ['Q', 'i', 'K', 'u']
    results = ime.Feed(key)
  endfor
  assert.equals(len(results), 1)
  assert.equals(results[0].registration_requested, true)
  assert.equals(results[0].in_candidate, false)
  assert.equals(results[0].state.reading, 'い')
  assert.equals(results[0].state.okuri, 'く')
  assert.equals(ime.GetCandidates().query.lookup_key, 'いk')
  assert.equals(ime.GetCandidates().candidates, [])
  assert.equals(preferences.GetSnapshot().entries, {})
  assert.equals(preferences.GetSnapshot().mru, {})
}

suite.latent_boundary_without_okuri_text_waits_for_the_first_okuri_output = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const compiled = scheme.Compile({q: '', k: 'k'}, {i: 'i*', u: 'u'})
  const ime = session.Session.new(compiled, '', entries, user_state.State.new())
  ime.Feed('Q')
  const initial = ime.Feed('I')
  assert.equals(initial[0].state.okuri_started, true)
  assert.equals(initial[0].state.okuri, '')
  assert.equals(ime.InCandidate(), false)
  ime.Feed('k')
  const completed = ime.Feed('u')
  assert.equals(completed[0].text, '行く')
  assert.equals(completed[0].in_candidate, true)
}

suite.remaining_special_output_commits_an_automatically_started_conversion_first = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const preferences = user_state.State.new()
  const compiled = scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['a', 'b'], 'い*く'),
    scheme.SpecialDefinition.new(['a', 'b', 'c', 'z'], '長'),
    scheme.SpecialDefinition.new(['c', 'x'], '。'),
  ])
  const ime = session.Session.new(compiled, '', entries, preferences)
  for key in ['A', 'B', 'c']
    assert.equals(ime.Feed(key), [])
  endfor
  const results = ime.Feed('x')
  assert.equals(len(results), 3)
  assert.equals(results[0].text, '行く')
  assert.equals(results[0].in_candidate, true)
  assert.equals(results[1].text, '行く')
  assert.equals(results[1].commit_preedit, true)
  assert.equals(results[2].text, '。')
  assert.equals(results[2].state.in_preedit, false)
  assert.equals(preferences.GetSnapshot().mru[json_encode(['い', 'く'])], ['行'])
}
