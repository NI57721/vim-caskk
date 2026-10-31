vim9script

import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme

final suite = themis#suite('input session')
const assert = themis#helper('assert')

suite.redundant_sticky_and_uppercase_input_produce_the_same_preedit = (): void => {
  for keys in ['Ka', ';Ka', 'K;a', ';;;;;ka']
    const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
    for key in split(keys, '\zs')
      for result in ime.Feed(key)
        assert.equals(result.unhandled, [])
        assert.equals(result.text, '')
      endfor
    endfor
    assert.equals(ime.GetSnapshot().in_preedit, true)
    assert.equals(ime.GetSnapshot().reading, 'か')
    assert.equals(ime.GetSnapshot().okuri, '')
    assert.equals(ime.Pending(), [])
    ime.Feed('k')
    ime.Feed('a')
    assert.equals(ime.GetSnapshot().reading, 'かか')
    assert.equals(ime.GetSnapshot().okuri, '')
  endfor
}

suite.normal_input_returns_direct_text_after_the_second_key = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  assert.equals(ime.Feed('k'), [])
  assert.equals(len(ime.Pending()), 1)
  assert.equals(ime.Pending()[0].key, 'k')
  const results = ime.Feed('a')
  assert.equals(len(results), 1)
  assert.equals(results[0].text, 'か')
  assert.equals(results[0].unhandled, [])
  assert.equals(results[0].state.in_preedit, false)
  assert.equals(results[0].state.reading, '')
  assert.equals(ime.Pending(), [])
}

suite.uppercase_and_sticky_keys_start_normal_okuri = (): void => {
  const compiled = scheme.Compile({k: 'k', j: 'z'}, {l: 'aN', i: 'i'})
  for keys in [['K', 'l', 'J', 'i'], [';', 'k', 'l', ';', 'j', 'i']]
    const ime = session.Session.new(compiled, ';')
    for key in keys
      for result in ime.Feed(key)
        assert.equals(result.text, '')
        assert.equals(result.unhandled, [])
      endfor
    endfor
    const snapshot = ime.GetSnapshot()
    assert.equals(snapshot.in_preedit, true)
    assert.equals(snapshot.reading, 'かん')
    assert.equals(snapshot.okuri, 'じ')
    assert.equals(snapshot.okuri_started, true)
    assert.equals(ime.Pending(), [])
  endfor
}

suite.modified_combination_activates_latent_boundary = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {l: 'o*N'})
  for keys in [['K', 'L'], [';', 'k', ';', 'l']]
    const ime = session.Session.new(compiled, ';')
    var results: list<session.Result> = []
    for key in keys
      results = ime.Feed(key)
    endfor
    assert.equals(len(results), 1)
    assert.equals(results[0].text, '')
    assert.equals(results[0].state.reading, 'こ')
    assert.equals(results[0].state.okuri, 'ん')
    assert.equals(results[0].state.okuri_started, true)
  endfor
}

suite.special_prefix_delays_normal_output = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['k', 'a', 'b'], '特別'),
  ])
  const ime = session.Session.new(compiled)
  assert.equals(ime.Feed('k'), [])
  assert.equals(ime.Feed('a'), [])
  assert.equals(len(ime.Pending()), 2)
  const results = ime.Feed('b')
  assert.equals(len(results), 1)
  assert.equals(results[0].text, '特別')
  assert.equals(results[0].unhandled, [])
  assert.equals(ime.Pending(), [])
}

suite.failed_special_returns_normal_text_before_unhandled_input = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['k', 'a', 'b'], '特別'),
  ])
  const ime = session.Session.new(compiled)
  assert.equals(ime.Feed('k'), [])
  assert.equals(ime.Feed('a'), [])
  const results = ime.Feed('x')
  assert.equals(len(results), 2)
  assert.equals(results[0].text, 'か')
  assert.equals(results[0].unhandled, [])
  assert.equals(results[1].text, '')
  assert.equals(len(results[1].unhandled), 1)
  assert.equals(results[1].unhandled[0].key, 'x')
  assert.equals(results[1].state.in_preedit, false)
  assert.equals(ime.Pending(), [])
}

suite.fallback_returns_consecutive_specials_in_order = (): void => {
  const compiled = scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['a'], '先頭'),
    scheme.SpecialDefinition.new(['a', 'b', 'c'], '長'),
    scheme.SpecialDefinition.new(['b', 'x'], '末尾'),
  ])
  const ime = session.Session.new(compiled)
  assert.equals(ime.Feed('a'), [])
  assert.equals(ime.Feed('b'), [])
  const results = ime.Feed('x')
  assert.equals(len(results), 2)
  assert.equals(results[0].text, '先頭')
  assert.equals(results[1].text, '末尾')
  assert.equals(ime.Pending(), [])
}

suite.direct_output_snapshot_precedes_preedit_started_in_the_same_feed = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['k', 'a', 'z'], '長'),
    scheme.SpecialDefinition.new(['x'], 'よ'),
  ])
  const ime = session.Session.new(compiled)
  assert.equals(ime.Feed('k'), [])
  assert.equals(ime.Feed('a'), [])
  const results = ime.Feed('X')
  assert.equals(len(results), 2)
  assert.equals(results[0].text, 'か')
  assert.equals(results[0].state.in_preedit, false)
  assert.equals(results[0].state.reading, '')
  assert.equals(results[1].text, '')
  assert.equals(results[1].state.in_preedit, true)
  assert.equals(results[1].state.reading, 'よ')
  assert.equals(ime.GetSnapshot().reading, 'よ')
}

suite.each_result_is_interpreted_using_the_updated_preedit_state = (): void => {
  const compiled = scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['a'], 'さ'),
    scheme.SpecialDefinition.new(['a', 'b', 'c', 'z'], '長'),
    scheme.SpecialDefinition.new(['b', 'c', 'x'], 'か*ける'),
  ])
  const ime = session.Session.new(compiled)
  assert.equals(ime.Feed('A'), [])
  assert.equals(ime.Feed('b'), [])
  assert.equals(ime.Feed('c'), [])
  const results = ime.Feed('X')
  assert.equals(len(results), 2)
  assert.equals(results[0].state.reading, 'さ')
  assert.equals(results[0].state.okuri, '')
  assert.equals(results[0].state.okuri_started, false)
  assert.equals(results[1].state.reading, 'さか')
  assert.equals(results[1].state.okuri, 'ける')
  assert.equals(results[1].state.okuri_started, true)
  assert.equals(results[0].state.reading, 'さ')
}

suite.custom_sticky_key_and_unhandled_tokens_are_preserved = (): void => {
  const ime = session.Session.new(scheme.Compile({}, {}), '<M-j>')
  assert.equals(ime.Feed('<M-j>'), [])
  const results = ime.Feed('<C-x>')
  assert.equals(len(results), 1)
  assert.equals(results[0].text, '')
  assert.equals(len(results[0].unhandled), 1)
  assert.equals(results[0].unhandled[0].key, '<C-x>')
  assert.equals(results[0].unhandled[0].modified, true)
  assert.equals(results[0].state.in_preedit, false)
  assert.equals(results[0].state.reading, '')
}

suite.unhandled_input_does_not_change_preedit = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  assert.equals(ime.Feed('K'), [])
  const initial = ime.Feed('a')
  assert.equals(initial[0].state.reading, 'か')
  const results = ime.Feed('!')
  assert.equals(len(results), 1)
  assert.equals(results[0].unhandled[0].key, '!')
  assert.equals(results[0].state.in_preedit, true)
  assert.equals(results[0].state.reading, 'か')
  assert.equals(results[0].state.okuri, '')
}

suite.empty_special_is_handled_and_can_start_preedit = (): void => {
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['x'], '')])
  const ime = session.Session.new(compiled)
  const ordinary = ime.Feed('x')
  assert.equals(len(ordinary), 1)
  assert.equals(ordinary[0].text, '')
  assert.equals(ordinary[0].unhandled, [])
  assert.equals(ordinary[0].state.in_preedit, false)
  const modified = ime.Feed('X')
  assert.equals(len(modified), 1)
  assert.equals(modified[0].text, '')
  assert.equals(modified[0].unhandled, [])
  assert.equals(modified[0].state.in_preedit, true)
  assert.equals(modified[0].state.reading, '')
  assert.equals(ime.Pending(), [])
}

suite.sessions_do_not_share_sticky_or_pending_input = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'})
  const first = session.Session.new(compiled, ';')
  const second = session.Session.new(compiled, ';')
  assert.equals(first.Feed(';'), [])
  assert.equals(second.Feed('k'), [])
  assert.equals(first.Pending(), [])
  const direct = second.Feed('a')
  assert.equals(direct[0].text, 'か')
  assert.equals(direct[0].state.in_preedit, false)
  assert.equals(first.Feed('k'), [])
  assert.equals(second.Pending(), [])
  const preedit = first.Feed('a')
  assert.equals(preedit[0].text, '')
  assert.equals(preedit[0].state.in_preedit, true)
  assert.equals(preedit[0].state.reading, 'か')
}

suite.initial_snapshot_remains_unchanged_after_input = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  const initial = ime.GetSnapshot()
  assert.equals(ime.Feed('K'), [])
  const results = ime.Feed('a')
  assert.equals(results[0].state.in_preedit, true)
  assert.equals(initial.in_preedit, false)
  assert.equals(initial.reading, '')
  assert.equals(initial.okuri, '')
  assert.equals(initial.okuri_started, false)
}

suite.commit_returns_reading_and_okuri_and_resets_preedit = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k', j: 'z'}, {l: 'aN', i: 'i'}))
  for key in ['K', 'l', 'J', 'i']
    ime.Feed(key)
  endfor
  const previous = ime.GetSnapshot()
  const results = ime.Commit()
  assert.equals(len(results), 1)
  assert.equals(results[0].text, 'かんじ')
  assert.equals(results[0].commit_preedit, true)
  assert.equals(results[0].unhandled, [])
  assert.equals(results[0].state.in_preedit, false)
  assert.equals(results[0].state.reading, '')
  assert.equals(results[0].state.okuri, '')
  assert.equals(results[0].state.okuri_started, false)
  assert.equals(previous.reading, 'かん')
  assert.equals(previous.okuri, 'じ')
  assert.equals(ime.Commit(), [])
  assert.equals(ime.Feed('k'), [])
  const next = ime.Feed('l')
  assert.equals(next[0].text, 'かん')
  assert.equals(next[0].state.in_preedit, false)
}

suite.commit_resolves_pending_special_before_committing_preedit = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['k', 'a'], '短'),
    scheme.SpecialDefinition.new(['k', 'a', 'b'], '長'),
  ]
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(ime.Feed('K'), [])
  assert.equals(ime.Feed('a'), [])
  const results = ime.Commit()
  assert.equals(len(results), 2)
  assert.equals(results[0].text, '')
  assert.equals(results[0].commit_preedit, false)
  assert.equals(results[0].state.in_preedit, true)
  assert.equals(results[0].state.reading, '短')
  assert.equals(results[1].text, '短')
  assert.equals(results[1].commit_preedit, true)
  assert.equals(results[1].state.in_preedit, false)
  assert.equals(ime.Pending(), [])
}

suite.commit_interprets_flushed_specials_using_updated_state = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['a'], 'さ'),
    scheme.SpecialDefinition.new(['a', 'b', 'c', 'z'], '長'),
    scheme.SpecialDefinition.new(['b', 'c'], 'か*ける'),
  ]
  const ime = session.Session.new(scheme.Compile({}, {}, definitions))
  for key in ['A', 'b', 'C']
    assert.equals(ime.Feed(key), [])
  endfor
  const results = ime.Commit()
  assert.equals(len(results), 3)
  assert.equals(results[0].state.reading, 'さ')
  assert.equals(results[0].state.okuri, '')
  assert.equals(results[1].state.reading, 'さか')
  assert.equals(results[1].state.okuri, 'ける')
  assert.equals(results[1].commit_preedit, false)
  assert.equals(results[2].text, 'さかける')
  assert.equals(results[2].commit_preedit, true)
  assert.equals(results[2].state.in_preedit, false)
  assert.equals(ime.Pending(), [])
}

suite.commit_replays_incomplete_special_without_repeating_direct_output = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['k', 'a', 'b'], '特別')]
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(ime.Feed('k'), [])
  assert.equals(ime.Feed('a'), [])
  const results = ime.Commit()
  assert.equals(len(results), 1)
  assert.equals(results[0].text, 'か')
  assert.equals(results[0].commit_preedit, false)
  assert.equals(results[0].state.in_preedit, false)
  assert.equals(ime.Pending(), [])
  assert.equals(ime.Commit(), [])
}

suite.commit_returns_unfinished_consonant_without_losing_modified_information = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  assert.equals(ime.Feed('K'), [])
  ime.Feed('a')
  assert.equals(ime.Feed('K'), [])
  const results = ime.Commit()
  assert.equals(len(results), 2)
  assert.equals(results[0].text, '')
  assert.equals(results[0].unhandled[0].key, 'k')
  assert.equals(results[0].unhandled[0].modified, true)
  assert.equals(results[0].state.reading, 'か')
  assert.equals(results[0].commit_preedit, false)
  assert.equals(results[1].text, 'か')
  assert.equals(results[1].commit_preedit, true)
  assert.equals(ime.Pending(), [])
  assert.equals(ime.Feed('k'), [])
  assert.equals(ime.Feed('a')[0].text, 'か')
}

suite.commit_clears_sticky_modifier_in_direct_and_preedit = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'})
  for prefix in [[], ['K', 'a']]
    const ime = session.Session.new(compiled, ';')
    for key in prefix
      ime.Feed(key)
    endfor
    assert.equals(ime.Feed(';'), [])
    const committed = ime.Commit()
    if empty(prefix)
      assert.equals(committed, [])
    else
      assert.equals(len(committed), 1)
      assert.equals(committed[0].text, 'か')
      assert.equals(committed[0].commit_preedit, true)
    endif
    assert.equals(ime.Feed('k'), [])
    const next = ime.Feed('a')
    assert.equals(next[0].text, 'か')
    assert.equals(next[0].state.in_preedit, false)
  endfor
}

suite.commit_notifies_empty_preedit_and_is_idempotent = (): void => {
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['x'], '')])
  const ime = session.Session.new(compiled)
  assert.equals(ime.Feed('X')[0].state.in_preedit, true)
  const results = ime.Commit()
  assert.equals(len(results), 1)
  assert.equals(results[0].text, '')
  assert.equals(results[0].commit_preedit, true)
  assert.equals(results[0].state.in_preedit, false)
  assert.equals(ime.Commit(), [])
}
