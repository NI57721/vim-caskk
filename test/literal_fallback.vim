vim9script

import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('literal input fallback')
const assert = themis#helper('assert')

suite.failed_modified_combinations_fall_back_to_normalized_lowercase = (): void => {
  for keys in [['K', 'x'], [';', 'k', 'x']]
    const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
    var results: list<session.Result> = []
    for key in keys
      results = ime.Feed(key)
    endfor
    assert.equals(len(results), 2)
    assert.equals(results[0].text, 'k')
    assert.equals(results[1].text, 'x')
    for result in results
      assert.equals(result.unhandled, [])
      assert.equals(result.state.in_preedit, false)
    endfor
  endfor
}

suite.unknown_characters_extend_the_reading_used_for_conversion = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const results = ime.Feed('?')
  assert.equals(results[0].text, '')
  assert.equals(results[0].unhandled, [])
  assert.equals(results[0].state.in_preedit, true)
  assert.equals(results[0].state.reading, 'か?')
  const entries = merger.Merge([[parser.ParseLine('か? /可疑/')]])
  assert.equals(ime.StartConversion(entries, user_state.State.new())[0].text, '可疑')
}

suite.special_replay_preserves_reading_before_appending_literal_input = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [scheme.SpecialDefinition.new(['k', 'a', 'b'], '特別')])
  const ime = session.Session.new(compiled)
  assert.equals(ime.Feed('K'), [])
  assert.equals(ime.Feed('a'), [])
  const results = ime.Feed('x')
  assert.equals(len(results), 2)
  assert.equals(results[0].state.reading, 'か')
  assert.equals(results[1].state.reading, 'かx')
  assert.equals(results[1].state.in_preedit, true)
  assert.equals(results[1].unhandled, [])
}

suite.unmatched_modified_keys_do_not_create_an_okuri_boundary = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  for key in ['K', 'a', 'K', 'x']
    ime.Feed(key)
  endfor
  assert.equals(ime.GetSnapshot().reading, 'かkx')
  assert.equals(ime.GetSnapshot().okuri, '')
  assert.equals(ime.GetSnapshot().okuri_started, false)
}

suite.named_keys_and_control_characters_remain_unhandled_events = (): void => {
  for token in ['<F10>', '<CR>', "\n"]
    const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
    ime.Feed('K')
    ime.Feed('a')
    ime.Feed(';')
    const result = ime.Feed(token)[0]
    assert.equals(result.text, '')
    assert.equals(result.unhandled[0].key, token)
    assert.equals(result.unhandled[0].modified, true)
    assert.equals(result.state.reading, 'か')
  endfor
}

suite.unmapped_unicode_characters_are_preserved_as_text = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  assert.equals(ime.Feed('あ')[0].text, 'あ')
  ime.Feed('K')
  ime.Feed('a')
  assert.equals(ime.Feed('漢')[0].state.reading, 'か漢')
}

suite.literal_kana_can_complete_an_empty_okuri_boundary_and_start_conversion = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const ime = session.Session.new(scheme.Compile({q: ''}, {i: 'i*'}), '', entries)
  ime.Feed('Q')
  ime.Feed('I')
  assert.equals(ime.GetSnapshot().okuri, '')
  const result = ime.Feed('く')[0]
  assert.equals(result.text, '行く')
  assert.equals(result.in_candidate, true)
  assert.equals(result.state.reading, 'い')
  assert.equals(result.state.okuri, 'く')
}
