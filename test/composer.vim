vim9script

import 'caskk/input.vim' as input
import autoload 'caskk/composer.vim' as composer
import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme.vim' as scheme

final suite = themis#suite('input composition')
const assert = themis#helper('assert')

suite.backspace_removes_an_unfinished_modified_consonant_without_replaying_it = (): void => {
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  engine.Feed(input.Event.new('k', true))
  assert.equals(engine.Backspace(), true)
  assert.equals(engine.Pending(), [])
  const results = engine.Feed(input.Event.new('a'))
  assert.equals(results[0].output.text, 'あ')
  assert.equals(results[0].events[0].key, 'a')
}

suite.backspace_keeps_the_remaining_special_prefix_pending = (): void => {
  const compiled = scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['a'], '短'),
    scheme.SpecialDefinition.new(['a', 'b', 'c'], '長'),
  ])
  const engine = composer.Composer.new(compiled)
  engine.Feed(input.Event.new('a'))
  engine.Feed(input.Event.new('b', true))
  assert.equals(engine.Backspace(), true)
  assert.equals(len(engine.Pending()), 1)
  assert.equals(engine.Pending()[0].key, 'a')
  assert.equals(engine.Feed(input.Event.new('b')), [])
  const results = engine.Feed(input.Event.new('c'))
  assert.equals(results[0].output.text, '長')
  assert.equals(results[0].events[1].modified, false)
}

suite.backspace_removes_special_suffix_keys_before_an_older_consonant = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [scheme.SpecialDefinition.new(['x', 'y', 'z'], '特')])
  const engine = composer.Composer.new(compiled)
  for key in ['k', 'x', 'y']
    engine.Feed(input.Event.new(key))
  endfor
  assert.equals(engine.Backspace(), true)
  assert.equals(len(engine.Pending()), 2)
  assert.equals(engine.Pending()[0].key, 'k')
  assert.equals(engine.Pending()[1].key, 'x')
  assert.equals(engine.Backspace(), true)
  assert.equals(engine.Pending()[0].key, 'k')
  assert.equals(engine.Backspace(), true)
  assert.equals(engine.Pending(), [])
  assert.equals(engine.Backspace(), false)
}

suite.normal_combination_waits_for_second_key = (): void => {
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  const first = input.Event.new('k')
  const second = input.Event.new('a')
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Pending(), [first])
  const results = engine.Feed(second)
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'か')
  assert.equals(results[0].is_special, false)
  assert.equals(results[0].events, [first, second])
  assert.equals(engine.Pending(), [])
}

suite.pending_consonant_combination_precedes_same_key_special = (): void => {
  const compiled = scheme.Compile({j: 'zy'}, {'-': 'a*u'}, [
    scheme.SpecialDefinition.new(['-'], 'ー'),
  ])
  const engine = composer.Composer.new(compiled)
  assert.equals(engine.Feed(input.Event.new('j')), [])
  const results = engine.Feed(input.Event.new('-'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'じゃう')
  assert.equals(results[0].is_special, false)
  const standalone = engine.Feed(input.Event.new('-'))
  assert.equals(len(standalone), 1)
  assert.equals(standalone[0].output.text, 'ー')
  assert.equals(standalone[0].is_special, true)
}

suite.pending_consonant_combination_does_not_wait_for_a_longer_special = (): void => {
  const compiled = scheme.Compile({j: 'zy'}, {'-': 'a*u'}, [
    scheme.SpecialDefinition.new(['-', 'a'], '長いspecial'),
  ])
  const engine = composer.Composer.new(compiled)
  assert.equals(engine.Feed(input.Event.new('j')), [])
  const results = engine.Feed(input.Event.new('-'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'じゃう')
  assert.equals(results[0].is_special, false)
  const composed = composer.Compose(results[0])
  assert.equals(composed.reading, 'じゃう')
  assert.equals(composed.okuri, '')
}

suite.replayed_consonant_combination_precedes_other_special_prefixes = (): void => {
  const compiled = scheme.Compile({j: 'zy'}, {'-': 'a*u'}, [
    scheme.SpecialDefinition.new(['-', 'a'], 'ー'),
    scheme.SpecialDefinition.new(['j', 's'], 'ます'),
  ])
  const engine = composer.Composer.new(compiled)
  assert.equals(engine.Feed(input.Event.new('j')), [])
  const results = engine.Feed(input.Event.new('-'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'じゃう')
  assert.equals(results[0].is_special, false)
}

suite.replayed_consonant_combination_precedes_three_key_specials = (): void => {
  const compiled = scheme.Compile({j: 'zy'}, {'-': 'a*u'}, [
    scheme.SpecialDefinition.new(['-', 'a'], 'ー'),
    scheme.SpecialDefinition.new(['j', 's', 'n'], 'ません'),
  ])
  const engine = composer.Composer.new(compiled)
  assert.equals(engine.Feed(input.Event.new('j')), [])
  const results = engine.Feed(input.Event.new('-'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'じゃう')
  assert.equals(results[0].is_special, false)
  const composed = composer.Compose(results[0])
  assert.equals(composed.reading, 'じゃう')
  assert.equals(composed.okuri, '')
}

suite.replayed_consonant_combination_precedes_exact_single_key_special = (): void => {
  const compiled = scheme.Compile({j: 'zy'}, {'-': 'i*yo'}, [
    scheme.SpecialDefinition.new(['-'], 'ー'),
    scheme.SpecialDefinition.new(['j', 's', 'n'], 'ません'),
  ])
  const engine = composer.Composer.new(compiled)
  assert.equals(engine.Feed(input.Event.new('j')), [])
  const results = engine.Feed(input.Event.new('-'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'じよ')
  assert.equals(results[0].is_special, false)
}

suite.vowel_combination_composes_without_a_consonant = (): void => {
  const engine = composer.Composer.new(scheme.Compile({}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'}))
  const results = engine.Feed(input.Event.new('a'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'あ')
  assert.equals(results[0].events[0].key, 'a')
}

suite.standalone_combination_keeps_a_latent_okuri_boundary_inert = (): void => {
  const engine = composer.Composer.new(scheme.Compile({}, {'!': 'a*N'}))
  const matched = engine.Feed(input.Event.new('!'))
  assert.equals(len(matched), 1)
  const result = composer.Compose(matched[0])
  assert.equals(result.start_conversion, true)
  assert.equals(result.reading, 'あん')
  assert.equals(result.okuri, '')
  assert.equals(result.okuri_started, false)
}

suite.pending_special_recognizes_space_before_the_binding_action = (): void => {
  const engine = composer.Composer.new(scheme.Compile({}, {},
    scheme.SpecialDefinitions({'z ': '　'})))
  assert.equals(engine.Feed(input.Event.new('z')), [])
  assert.equals(engine.IsSpecialContinuation('<Space>'), true)
  const matched = engine.Feed(input.Event.new('<Space>'))
  assert.equals(len(matched), 1)
  assert.equals(matched[0].output.text, '　')
}

suite.special_overrides_generated_combination = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['k', 'a'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  const results = engine.Feed(input.Event.new('a'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '特別')
  assert.equals(results[0].is_special, true)
  assert.equals(engine.Pending(), [])
}

suite.special_prefix_delays_complete_normal_combination = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['k', 'a', 'b'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  const first = input.Event.new('k')
  const second = input.Event.new('a')
  const third = input.Event.new('b')
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Feed(second), [])
  assert.equals(engine.Pending(), [first, second])
  const results = engine.Feed(third)
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '特別')
  assert.equals(results[0].events, [first, second, third])
  assert.equals(engine.Pending(), [])
}

suite.exact_special_waits_for_longer_special = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['k', 'a'], '短'),
    scheme.SpecialDefinition.new(['k', 'a', 'b'], '長'),
  ]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('a')), [])
  const results = engine.Feed(input.Event.new('b'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '長')
}

suite.failed_special_replays_through_normal_composition = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['k', 'a', 'b'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  const first = input.Event.new('k')
  const second = input.Event.new('a')
  const third = input.Event.new('x')
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Feed(second), [])
  const results = engine.Feed(third)
  assert.equals(len(results), 2)
  assert.equals(results[0].output.text, 'か')
  assert.equals(results[0].events, [first, second])
  assert.equals(results[1].output is null_object, true)
  assert.equals(results[1].events, [third])
  assert.equals(engine.Pending(), [])
}

suite.failed_longer_special_commits_shorter_special_before_normal_rules = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['k', 'a'], '短'),
    scheme.SpecialDefinition.new(['k', 'a', 'b'], '長'),
  ]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('a')), [])
  const results = engine.Feed(input.Event.new('x'))
  assert.equals(len(results), 2)
  assert.equals(results[0].output.text, '短')
  assert.equals(results[1].events[0].key, 'x')
  assert.equals(results[1].output is null_object, true)
  assert.equals(engine.Pending(), [])
}

suite.fallback_reprocesses_remaining_input_as_another_special = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['k', 'a'], '短'),
    scheme.SpecialDefinition.new(['k', 'a', 'b'], '長'),
    scheme.SpecialDefinition.new(['x', 'y'], '次'),
  ]
  const engine = composer.Composer.new(scheme.Compile({k: 'k', x: 'n'}, {a: 'a', y: 'a'}, definitions))
  const first = input.Event.new('k', true)
  const second = input.Event.new('a')
  const rest = input.Event.new('x', true)
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Feed(second), [])
  const results = engine.Feed(rest)
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '短')
  assert.equals(results[0].events, [first, second])
  assert.equals(engine.Pending(), [rest])
  const last = input.Event.new('y')
  const next_results = engine.Feed(last)
  assert.equals(len(next_results), 1)
  assert.equals(next_results[0].output.text, '次')
  assert.equals(next_results[0].events, [rest, last])
  assert.equals(engine.Pending(), [])
}

suite.fallback_reprocesses_remaining_input_as_normal_combination = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['k', 'a'], '短'),
    scheme.SpecialDefinition.new(['k', 'a', 'b'], '長'),
  ]
  const engine = composer.Composer.new(scheme.Compile({k: 'k', n: 'n'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('a')), [])
  const rest = input.Event.new('n')
  const results = engine.Feed(rest)
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '短')
  assert.equals(engine.Pending(), [rest])
  const next_results = engine.Feed(input.Event.new('a'))
  assert.equals(len(next_results), 1)
  assert.equals(next_results[0].output.text, 'な')
  assert.equals(engine.Pending(), [])
}

suite.fallback_reprocesses_buffered_special_and_normal_input_in_order = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['a'], '短'),
    scheme.SpecialDefinition.new(['a', 'b', 'c', 'z'], '長'),
    scheme.SpecialDefinition.new(['b'], '次'),
  ]
  const engine = composer.Composer.new(scheme.Compile({c: 'k'}, {x: 'a'}, definitions))
  const first = input.Event.new('a')
  const second = input.Event.new('b', true)
  const third = input.Event.new('c')
  const fourth = input.Event.new('x')
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Feed(second), [])
  assert.equals(engine.Feed(third), [])
  const results = engine.Feed(fourth)
  assert.equals(len(results), 3)
  assert.equals(results[0].output.text, '短')
  assert.equals(results[0].events, [first])
  assert.equals(results[1].output.text, '次')
  assert.equals(results[1].events, [second])
  assert.equals(results[2].output.text, 'か')
  assert.equals(results[2].events, [third, fourth])
  assert.equals(engine.Pending(), [])
}

suite.empty_special_remains_prioritized_when_longer_special_fails = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['k', 'a'], ''),
    scheme.SpecialDefinition.new(['k', 'a', 'b'], '長'),
  ]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('a')), [])
  const results = engine.Feed(input.Event.new('x'))
  assert.equals(len(results), 2)
  assert.equals(results[0].output.text, '')
  assert.equals(results[1].output is null_object, true)
  assert.equals(results[1].events[0].key, 'x')
  assert.equals(engine.Pending(), [])
}

suite.replay_can_emit_multiple_normal_combinations = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['k', 'a', 'n', 'a', 'z'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k', n: 'n'}, {a: 'a'}, definitions))
  for key in ['k', 'a', 'n', 'a']
    assert.equals(engine.Feed(input.Event.new(key)), [])
  endfor
  const results = engine.Feed(input.Event.new('x'))
  assert.equals(len(results), 3)
  assert.equals(results[0].output.text, 'か')
  assert.equals(results[1].output.text, 'な')
  assert.equals(results[2].output is null_object, true)
  assert.equals(results[2].events[0].key, 'x')
  assert.equals(engine.Pending(), [])
}

suite.failure_keeps_suffix_that_can_start_another_special = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['k', 'a', 'z'], '甲'),
    scheme.SpecialDefinition.new(['a', 'b'], '乙'),
  ]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('a')), [])
  const suffix = input.Event.new('a', true)
  const replayed = engine.Feed(suffix)
  assert.equals(len(replayed), 1)
  assert.equals(replayed[0].output.text, 'か')
  assert.equals(engine.Pending(), [suffix])
  const results = engine.Feed(input.Event.new('b'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '乙')
  assert.equals(results[0].events[0].modified, true)
  assert.equals(engine.Pending(), [])
}

suite.replayed_combination_precedes_a_special_starting_at_its_suffix = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['k', 'a', 'z'], '甲'),
    scheme.SpecialDefinition.new(['a', 'b'], '乙'),
  ]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  const first = input.Event.new('k', true)
  const second = input.Event.new('a')
  const third = input.Event.new('b')
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Feed(second), [])
  const results = engine.Feed(third)
  assert.equals(len(results), 2)
  assert.equals(results[0].output.text, 'か')
  assert.equals(results[0].events, [first, second])
  assert.equals(results[1].output is null_object, true)
  assert.equals(results[1].events, [third])
  assert.equals(engine.Pending(), [])
}

suite.special_can_start_on_a_non_combination_key_while_consonant_is_pending = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['x', 'y'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  const first = input.Event.new('k')
  const second = input.Event.new('x')
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Feed(second), [])
  assert.equals(engine.Pending(), [first, second])
  const results = engine.Feed(input.Event.new('y'))
  assert.equals(len(results), 2)
  assert.equals(results[0].events, [first])
  assert.equals(results[0].output is null_object, true)
  assert.equals(results[1].output.text, '特別')
  assert.equals(engine.Pending(), [])
}

suite.pending_combination_completes_before_a_special_prefix_can_fail = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['a', 'b'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  const combined = engine.Feed(input.Event.new('a'))
  assert.equals(len(combined), 1)
  assert.equals(combined[0].output.text, 'か')
  const results = engine.Feed(input.Event.new('x'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output is null_object, true)
  assert.equals(results[0].events[0].key, 'x')
  assert.equals(engine.Pending(), [])
}

suite.replay_preserves_modified_input_and_generated_okuri_boundary = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['j', 'l', 'x'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({j: 'ky'}, {l: 'o*N'}, definitions))
  const first = input.Event.new('j', true)
  const second = input.Event.new('l', true)
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Feed(second), [])
  const results = engine.Feed(input.Event.new('!'))
  assert.equals(len(results), 2)
  assert.equals(results[0].events, [first, second])
  assert.equals(results[0].output.text, 'きょん')
  assert.equals(results[0].output.boundary, 2)
  const composed = composer.Compose(results[0])
  assert.equals(composed.start_conversion, true)
  assert.equals(composed.reading, 'きょ')
  assert.equals(composed.okuri, 'ん')
}

suite.single_key_special_can_suppress_normal_input = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['k'], '')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  const event = input.Event.new('k')
  const results = engine.Feed(event)
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '')
  assert.equals(results[0].events, [event])
  assert.equals(engine.Pending(), [])
}

suite.key_tokens_remain_opaque = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['<C-x>', 'あ'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({'<C-x>': 'k'}, {'あ': 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('<C-x>')), [])
  const results = engine.Feed(input.Event.new('あ'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '特別')
}

suite.unmatched_consonant_is_returned_before_next_combination = (): void => {
  const engine = composer.Composer.new(scheme.Compile({k: 'k', n: 'n'}, {a: 'a'}))
  const first = input.Event.new('k')
  const second = input.Event.new('n')
  assert.equals(engine.Feed(first), [])
  const unmatched = engine.Feed(second)
  assert.equals(len(unmatched), 1)
  assert.equals(unmatched[0].events, [first])
  assert.equals(unmatched[0].output is null_object, true)
  assert.equals(engine.Pending(), [second])
  const results = engine.Feed(input.Event.new('a'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'な')
}

suite.composers_have_independent_pending_input = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'})
  const first = composer.Composer.new(compiled)
  const second = composer.Composer.new(compiled)
  const event = input.Event.new('k')
  assert.equals(first.Feed(event), [])
  assert.equals(second.Pending(), [])
  assert.equals(first.Pending(), [event])
}

suite.pending_returns_a_copy = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['k', 'a'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  const event = input.Event.new('k')
  assert.equals(engine.Feed(event), [])
  var pending = engine.Pending()
  remove(pending, 0)
  assert.equals(engine.Pending(), [event])
}

suite.modified_special_starts_okuri_before_the_whole_output = (): void => {
  const compiled = scheme.Compile({j: 'z'}, {i: 'i'}, [scheme.SpecialDefinition.new(['j', 'i'], 'じ')])
  const engine = composer.Composer.new(compiled)
  assert.equals(engine.Feed(input.Event.new('j', true)), [])
  const results = engine.Feed(input.Event.new('i'))
  const composed = composer.Compose(results[0], true)
  assert.equals(composed.start_conversion, false)
  assert.equals(composed.reading, '')
  assert.equals(composed.okuri, 'じ')
  assert.equals(composed.okuri_started, true)
}

suite.modified_single_key_special_starts_okuri = (): void => {
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['x'], 'じ')])
  const engine = composer.Composer.new(compiled)
  const results = engine.Feed(input.Event.new('x', true))
  assert.equals(len(results), 1)
  const composed = composer.Compose(results[0], true)
  assert.equals(composed.start_conversion, false)
  assert.equals(composed.reading, '')
  assert.equals(composed.okuri, 'じ')
  assert.equals(composed.okuri_started, true)
}

suite.modified_nasal_and_sokuon_consonants_start_okuri_in_preedit = (): void => {
  const compiled = scheme.Compile({q: 'N', l: 'T'}, {})
  for [key, kana] in [['q', 'ん'], ['l', 'っ']]
    const engine = composer.Composer.new(compiled)
    const results = engine.Feed(input.Event.new(key, true))
    assert.equals(len(results), 1)
    assert.equals(results[0].is_symbol, true)
    const composed = composer.Compose(results[0], true)
    assert.equals(composed.reading, '')
    assert.equals(composed.okuri, kana)
    assert.equals(composed.okuri_started, true)
  endfor
}

suite.failed_special_is_interpreted_as_normal_input = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['j', 'i', 'x'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({j: 'z'}, {i: 'i'}, definitions))
  assert.equals(engine.Feed(input.Event.new('j', true)), [])
  assert.equals(engine.Feed(input.Event.new('i')), [])
  const results = engine.Feed(input.Event.new('!'))
  assert.equals(len(results), 2)
  assert.equals(results[0].is_special, false)
  const composed = composer.Compose(results[0], true)
  assert.equals(composed.reading, '')
  assert.equals(composed.okuri, 'じ')
  assert.equals(composed.okuri_started, true)
}

suite.unmatched_input_cannot_be_interpreted_as_composed_text = (): void => {
  const engine = composer.Composer.new(scheme.Compile({}, {}))
  const results = engine.Feed(input.Event.new('!'))
  var caught = ''
  try
    composer.Compose(results[0])
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: cannot compose unmatched input')
}

suite.flush_replays_incomplete_special_as_normal_input = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['k', 'a', 'b'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('a')), [])
  const results = engine.Flush()
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'か')
  assert.equals(results[0].is_special, false)
  assert.equals(engine.Pending(), [])
  assert.equals(engine.Flush(), [])
}

suite.flush_prioritizes_complete_special_over_normal_combination = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['k', 'a'], '短'),
    scheme.SpecialDefinition.new(['k', 'a', 'b'], '長'),
  ]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('a')), [])
  const results = engine.Flush()
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '短')
  assert.equals(results[0].is_special, true)
  assert.equals(engine.Pending(), [])
}

suite.flush_returns_unmatched_consonant_with_modified_information = (): void => {
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  const event = input.Event.new('k', true)
  assert.equals(engine.Feed(event), [])
  const results = engine.Flush()
  assert.equals(len(results), 1)
  assert.equals(results[0].output is null_object, true)
  assert.equals(results[0].events, [event])
  assert.equals(engine.Pending(), [])
  assert.equals(engine.Flush(), [])
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('a'))[0].output.text, 'か')
}

suite.flush_reprocesses_remaining_specials_in_order = (): void => {
  const definitions = [
    scheme.SpecialDefinition.new(['a'], '先頭'),
    scheme.SpecialDefinition.new(['a', 'b', 'c', 'z'], '長'),
    scheme.SpecialDefinition.new(['b', 'c'], '末尾'),
  ]
  const engine = composer.Composer.new(scheme.Compile({}, {}, definitions))
  for key in ['a', 'b', 'c']
    assert.equals(engine.Feed(input.Event.new(key)), [])
  endfor
  const results = engine.Flush()
  assert.equals(len(results), 2)
  assert.equals(results[0].output.text, '先頭')
  assert.equals(results[1].output.text, '末尾')
  assert.equals(engine.Pending(), [])
}

suite.combination_completes_before_flush_when_key_starts_a_special = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['a', 'b'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  const combined = engine.Feed(input.Event.new('a'))
  assert.equals(len(combined), 1)
  assert.equals(combined[0].output.text, 'か')
  assert.equals(engine.Flush(), [])
  assert.equals(engine.Pending(), [])
}

suite.sokuon_prefix_outputs_immediately_and_retains_a_consonant = (): void => {
  const engine = composer.Composer.new(scheme.Compile({k: 'k', kk: 'Tk'}, {a: 'a'}))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  for count in range(1, 3)
    const results = engine.Feed(input.Event.new('k'))
    assert.equals(len(results), 1)
    assert.equals(results[0].output.text, 'っ')
    assert.equals(mapnew(engine.Pending(), (_, e) => e.key), ['k'])
  endfor
  assert.equals(engine.Feed(input.Event.new('a'))[0].output.text, 'か')
  assert.equals(engine.Pending(), [])
}

suite.sokuon_prefix_keeps_its_row_without_a_matching_single_key_definition = (): void => {
  const engine = composer.Composer.new(scheme.Compile({q: 'Tky'}, {a: 'a*iN'}))
  assert.equals(engine.Feed(input.Event.new('q'))[0].output.text, 'っ')
  assert.equals(engine.Feed(input.Event.new('a', true))[0].output.text, 'きゃいん')
  engine.Feed(input.Event.new('q'))
  assert.equals(engine.Backspace(), true)
  assert.equals(engine.Pending(), [])
  assert.equals(engine.Feed(input.Event.new('a'))[0].output.text, 'あいん')
}

suite.sokuon_prefix_respects_longer_consonants_and_specials = (): void => {
  const engine = composer.Composer.new(scheme.Compile({k: 'k', kk: 'Tk', kky: 'Tky'}, {a: 'a'}))
  engine.Feed(input.Event.new('k'))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('y'))[0].output.text, 'っ')
  assert.equals(engine.Feed(input.Event.new('a'))[0].output.text, 'きゃ')
  const overridden = composer.Composer.new(scheme.Compile({k: 'k', kk: 'Tk'}, {a: 'a'},
    [scheme.SpecialDefinition.new(['k', 'k'], '特')]))
  overridden.Feed(input.Event.new('k'))
  assert.equals(overridden.Feed(input.Event.new('k'))[0].output.text, '特')
  assert.equals(overridden.Pending(), [])
}

suite.sokuon_prefix_resolves_delayed_matches_and_flushes_the_retained_key = (): void => {
  for finish in ['a', 'flush']
    const engine = composer.Composer.new(scheme.Compile({k: 'k', kk: 'Tk', kky: 'Tky'}, {a: 'a'}))
    engine.Feed(input.Event.new('k'))
    engine.Feed(input.Event.new('k'))
    const results = finish == 'flush' ? engine.Flush() : engine.Feed(input.Event.new('a'))
    assert.equals(results[0].output.text, 'っ')
    if finish == 'flush'
      assert.equals(results[1].output is null_object, true)
      assert.equals(results[1].events[0].key, 'k')
    else
      assert.equals(results[1].output.text, 'か')
    endif
    assert.equals(engine.Pending(), [])
  endfor
}

suite.retained_sokuon_row_extends_and_backspaces_as_physical_input = (): void => {
  const engine = composer.Composer.new(scheme.Compile({k: 'k', kk: 'Tk', ky: 'ky'}, {a: 'a'}))
  engine.Feed(input.Event.new('k'))
  engine.Feed(input.Event.new('k'))
  engine.Feed(input.Event.new('y'))
  assert.equals(engine.Feed(input.Event.new('a'))[0].output.text, 'きゃ')
  engine.Feed(input.Event.new('k'))
  engine.Feed(input.Event.new('k'))
  engine.Feed(input.Event.new('y'))
  assert.equals(engine.Backspace(), true)
  assert.equals(engine.Feed(input.Event.new('a'))[0].output.text, 'か')
}

suite.special_continuation_does_not_capture_an_action_after_a_shorter_match = (): void => {
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['n'], 'ん'),
    scheme.SpecialDefinition.new(['n', 'a'], 'な'),
    scheme.SpecialDefinition.new(['z', '<Space>'], '　')])
  const engine = composer.Composer.new(compiled)
  engine.Feed(input.Event.new('n'))
  assert.equals(engine.IsSpecialContinuation('<Space>'), false)
  assert.equals(engine.IsSpecialContinuation('a'), true)
  const symbol = composer.Composer.new(compiled)
  symbol.Feed(input.Event.new('z'))
  assert.equals(symbol.IsSpecialContinuation('<Space>'), true)
}

suite.sokuon_retained_consonant_is_matched_against_specials = (): void => {
  const compiled = scheme.Compile({t: 't', tt: 'Tt'}, {a: 'a'},
    [scheme.SpecialDefinition.new(['t', 'a'], 'だ')])
  const engine = composer.Composer.new(compiled)
  engine.Feed(input.Event.new('t'))
  const doubled = engine.Feed(input.Event.new('t'))
  assert.equals(len(doubled), 1)
  assert.equals(doubled[0].output.text, 'っ')
  assert.equals(engine.Pending()[0].key, 't')
  const ending = engine.Feed(input.Event.new('a'))
  assert.equals(ending[0].output.text, 'だ')
  assert.equals(ending[0].is_special, true)
  assert.equals(engine.Pending(), [])
}

suite.same_start_special_delays_and_overrides_sokuon = (): void => {
  const engine = composer.Composer.new(scheme.Compile({t: 't', tt: 'Tt'}, {a: 'a'},
    [scheme.SpecialDefinition.new(['t', 'a'], 'だ'),
     scheme.SpecialDefinition.new(['t', 't', 'a'], '特別')]))
  engine.Feed(input.Event.new('t'))
  assert.equals(engine.Feed(input.Event.new('t')), [])
  assert.equals(engine.Feed(input.Event.new('a'))[0].output.text, '特別')
}

suite.sokuon_row_survives_a_failed_same_start_special = (): void => {
  const compiled = scheme.Compile({q: 'Tky'}, {a: 'a', i: 'i'},
    [scheme.SpecialDefinition.new(['q', 'a', 'z'], '特別')])
  const engine = composer.Composer.new(compiled)
  # A longer same-start special initially delays the output prefix.
  engine.Feed(input.Event.new('q'))
  const failed = engine.Feed(input.Event.new('i'))
  assert.equals(mapnew(failed, (_, r) => r.output.text), ['っ', 'き'])
  assert.equals(engine.Pending(), [])
}

suite.multi_key_consonant_precedes_a_suffix_special = (): void => {
  const engine = composer.Composer.new(scheme.Compile({k: 'k', ky: 'ky'}, {a: 'a'},
    [scheme.SpecialDefinition.new(['y', 'a'], '別')]))
  engine.Feed(input.Event.new('k'))
  assert.equals(engine.Feed(input.Event.new('y')), [])
  assert.equals(engine.Feed(input.Event.new('a'))[0].output.text, 'きゃ')
}

suite.retained_consonant_keeps_its_row_while_a_special_is_pending = (): void => {
  for finish in ['fail', 'backspace', 'flush']
    const engine = composer.Composer.new(scheme.Compile({t: 't', tt: 'Tt'}, {a: 'a', i: 'i'},
      [scheme.SpecialDefinition.new(['t', 'a', 'z'], '特別')]))
    engine.Feed(input.Event.new('t'))
    assert.equals(engine.Feed(input.Event.new('t'))[0].output.text, 'っ')
    assert.equals(engine.Feed(input.Event.new('a')), [])
    assert.equals(mapnew(engine.Pending(), (_, e) => e.key), ['t', 'a'])
    if finish == 'backspace'
      assert.equals(engine.Backspace(), true)
      assert.equals(engine.Feed(input.Event.new('i'))[0].output.text, 'ち')
    elseif finish == 'flush'
      assert.equals(engine.Flush()[0].output.text, 'た')
    else
      const results = engine.Feed(input.Event.new('b'))
      assert.equals(results[0].output.text, 'た')
      assert.equals(results[1].events[0].key, 'b')
    endif
    assert.equals(engine.Pending(), [])
  endfor
}
