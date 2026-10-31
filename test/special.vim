vim9script

import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme/output_pattern.vim' as output_pattern

final suite = themis#suite('special matching')
const assert = themis#helper('assert')

suite.prefix_waits_until_unambiguous_match = (): void => {
  const rules = [special.Rule.new(['j', 's', 'n'], output_pattern.Parse('ません'))]
  const match = special.Match(rules, ['j'])
  assert.equals(match.replay, [])
  assert.equals(match.pending, ['j'])
  assert.equals(match.output is null_object, true)
  const next_match = special.Match(rules, ['j', 's'])
  assert.equals(next_match.replay, [])
  assert.equals(next_match.pending, ['j', 's'])
  assert.equals(next_match.output is null_object, true)
  const result = special.Match(rules, ['j', 's', 'n'])
  assert.equals(result.replay, [])
  assert.equals(result.pending, [])
  assert.equals(result.output.text, 'ません')
}

suite.exact_match_waits_when_longer_rule_exists = (): void => {
  const rules = [
    special.Rule.new(['a'], output_pattern.Parse('短')),
    special.Rule.new(['a', 'b'], output_pattern.Parse('長')),
  ]
  const match = special.Match(rules, ['a'])
  assert.equals(match.replay, [])
  assert.equals(match.pending, ['a'])
  assert.equals(match.output is null_object, true)
  assert.equals(special.Match(rules, ['a', 'b']).output.text, '長')
  const next_match = special.Match(rules, ['a', 'x'])
  assert.equals(next_match.replay, [])
  assert.equals(next_match.pending, [])
  assert.equals(next_match.output.text, '短')
  assert.equals(next_match.rest, ['x'])
}

suite.failure_commits_longest_complete_prefix = (): void => {
  const rules = [
    special.Rule.new(['a'], output_pattern.Parse('短')),
    special.Rule.new(['a', 'b', 'c'], output_pattern.Parse('中')),
    special.Rule.new(['a', 'b', 'c', 'd', 'e'], output_pattern.Parse('長')),
  ]
  const result = special.Match(rules, ['a', 'b', 'c', 'x'])
  assert.equals(result.replay, [])
  assert.equals(result.pending, [])
  assert.equals(result.output.text, '中')
  assert.equals(result.rest, ['x'])
}

suite.complete_prefix_precedes_overlapping_suffix_special = (): void => {
  const rules = [
    special.Rule.new(['a'], output_pattern.Parse('先頭')),
    special.Rule.new(['a', 'b', 'c'], output_pattern.Parse('長')),
    special.Rule.new(['b', 'x'], output_pattern.Parse('末尾')),
  ]
  const result = special.Match(rules, ['a', 'b', 'x'])
  assert.equals(result.replay, [])
  assert.equals(result.pending, [])
  assert.equals(result.output.text, '先頭')
  assert.equals(result.rest, ['b', 'x'])
}

suite.failure_replays_unmatched_keys = (): void => {
  const rules = [special.Rule.new(['j', 's', 'n'], output_pattern.Parse('ません'))]
  const match = special.Match(rules, ['j', 's', 'x'])
  assert.equals(match.replay, ['j', 's', 'x'])
  assert.equals(match.pending, [])
  assert.equals(match.output is null_object, true)
}

suite.failure_preserves_longest_suffix_prefix = (): void => {
  const rules = [
    special.Rule.new(['a', 'b', 'c'], output_pattern.Parse('甲')),
    special.Rule.new(['b', 'd'], output_pattern.Parse('乙')),
  ]
  const match = special.Match(rules, ['a', 'b', 'b'])
  assert.equals(match.replay, ['a', 'b'])
  assert.equals(match.pending, ['b'])
  assert.equals(match.output is null_object, true)
  assert.equals(special.Match(rules, ['a', 'b', 'd']).output.text, '乙')
  assert.equals(special.Match(rules, ['a', 'b', 'd']).replay, ['a'])
}

suite.key_tokens_are_not_split_into_characters = (): void => {
  const rules = [special.Rule.new(['<C-x>', 'あ'], output_pattern.Parse('か\**ける'))]
  const match = special.Match(rules, ['<C-x>'])
  assert.equals(match.replay, [])
  assert.equals(match.pending, ['<C-x>'])
  assert.equals(match.output is null_object, true)
  const result = special.Match(rules, ['<C-x>', 'あ'])
  assert.equals(result.output.text, 'か*ける')
  assert.equals(result.output.boundary, 2)
}

suite.empty_input_and_no_rules = (): void => {
  const match = special.Match([], [])
  assert.equals(match.replay, [])
  assert.equals(match.pending, [])
  assert.equals(match.output is null_object, true)
  const next_match = special.Match([], ['a'])
  assert.equals(next_match.replay, ['a'])
  assert.equals(next_match.pending, [])
  assert.equals(next_match.output is null_object, true)
}

suite.empty_output_is_a_match = (): void => {
  const rules = [special.Rule.new(['a'], output_pattern.Parse(''))]
  const result = special.Match(rules, ['a'])
  assert.equals(result.output.text, '')
  assert.equals(result.pending, [])
  assert.equals(result.replay, [])
}

suite.empty_rule_is_rejected = (): void => {
  var caught = ''
  try
    special.Rule.new([], output_pattern.Parse('かな'))
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: special requires at least one key')
}
