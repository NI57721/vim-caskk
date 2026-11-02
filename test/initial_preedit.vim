vim9script

import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('initial preedit reading')
const assert = themis#helper('assert')

suite.initial_reading_accepts_more_input_and_can_be_converted = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かか /科/')]])
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, preferences, 'か')
  assert.equals(ime.GetSnapshot().in_preedit, true)
  assert.equals(ime.GetSnapshot().reading, 'か')
  assert.equals(ime.GetCandidates() is null_object, true)
  assert.equals(ime.Feed('k'), [])
  const results = ime.Feed('a')
  assert.equals(results[0].text, '')
  assert.equals(results[0].state.reading, 'かか')
  const converted = ime.StartConversion(entries, preferences)
  assert.equals(converted[0].text, '科')
  assert.equals(converted[0].in_candidate, true)
}

suite.initial_reading_is_literal_text_without_output_pattern_parsing = (): void => {
  const reading = 'か*' .. nr2char(92)
  const ime = session.Session.new(scheme.Compile({}, {}), '', {}, null_object, reading)
  assert.equals(ime.GetSnapshot().reading, reading)
  assert.equals(ime.GetSnapshot().okuri, '')
  assert.equals(ime.GetSnapshot().okuri_started, false)
  assert.equals(ime.Commit()[0].text, reading)
}

suite.modified_input_after_initial_reading_starts_okuri_and_auto_conversion = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {u: 'u'}), '', entries, preferences, 'い')
  assert.equals(ime.Feed('K'), [])
  const results = ime.Feed('u')
  assert.equals(results[0].text, '行く')
  assert.equals(results[0].in_candidate, true)
  assert.equals(results[0].state.reading, 'い')
  assert.equals(results[0].state.okuri, 'く')
  assert.equals(ime.GetCandidates().query.exact_okuri, 'く')
}
