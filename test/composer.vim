vim9script

import 'caskk/input.vim' as input
import autoload 'caskk/composer.vim' as composer
import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme.vim' as scheme

final suite = themis#suite('input composition')
const assert = themis#helper('assert')

suite.normal_combination_waits_for_second_key = (): void => {
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  const first = input.Event.new('k')
  const second = input.Event.new('a')
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Pending(), [first])
  const results = engine.Feed(second)
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, 'か')
  assert.equals(results[0].events, [first, second])
  assert.equals(engine.Pending(), [])
}

suite.special_overrides_generated_combination = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['k', 'a'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  const results = engine.Feed(input.Event.new('a'))
  assert.equals(len(results), 1)
  assert.equals(results[0].output.text, '特別')
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

suite.suffix_special_takes_precedence_over_replayed_consonant = (): void => {
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
  assert.equals(results[0].output is null_object, true)
  assert.equals(results[0].events, [first])
  assert.equals(results[1].output.text, '乙')
  assert.equals(results[1].events, [second, third])
  assert.equals(engine.Pending(), [])
}

suite.special_can_start_while_normal_consonant_is_pending = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['a', 'b'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  const first = input.Event.new('k')
  const second = input.Event.new('a')
  assert.equals(engine.Feed(first), [])
  assert.equals(engine.Feed(second), [])
  assert.equals(engine.Pending(), [first, second])
  const results = engine.Feed(input.Event.new('b'))
  assert.equals(len(results), 2)
  assert.equals(results[0].events, [first])
  assert.equals(results[0].output is null_object, true)
  assert.equals(results[1].output.text, '特別')
  assert.equals(engine.Pending(), [])
}

suite.failed_special_can_complete_preceding_normal_consonant = (): void => {
  const definitions = [scheme.SpecialDefinition.new(['a', 'b'], '特別')]
  const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}, definitions))
  assert.equals(engine.Feed(input.Event.new('k')), [])
  assert.equals(engine.Feed(input.Event.new('a')), [])
  const results = engine.Feed(input.Event.new('x'))
  assert.equals(len(results), 2)
  assert.equals(results[0].output.text, 'か')
  assert.equals(results[1].output is null_object, true)
  assert.equals(results[1].events[0].key, 'x')
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
  const composed = special.Compose(results[0].output, results[0].events)
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
