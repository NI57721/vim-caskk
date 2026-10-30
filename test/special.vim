vim9script

import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme/output_pattern.vim' as output_pattern

final suite = themis#suite('special matching')
const assert = themis#helper('assert')

suite.prefix_waits_until_unambiguous_match = (): void => {
  const rules = [special.Rule.new(['j', 's', 'n'], output_pattern.Parse('ません'))]
  assert.equals(special.Match(rules, ['j']), {replay: [], pending: ['j']})
  assert.equals(special.Match(rules, ['j', 's']), {replay: [], pending: ['j', 's']})
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
  assert.equals(special.Match(rules, ['a']), {replay: [], pending: ['a']})
  assert.equals(special.Match(rules, ['a', 'b']).output.text, '長')
  assert.equals(special.Match(rules, ['a', 'x']), {replay: ['a', 'x'], pending: []})
}

suite.failure_replays_unmatched_keys = (): void => {
  const rules = [special.Rule.new(['j', 's', 'n'], output_pattern.Parse('ません'))]
  assert.equals(special.Match(rules, ['j', 's', 'x']), {replay: ['j', 's', 'x'], pending: []})
}

suite.failure_preserves_longest_suffix_prefix = (): void => {
  const rules = [
    special.Rule.new(['a', 'b', 'c'], output_pattern.Parse('甲')),
    special.Rule.new(['b', 'd'], output_pattern.Parse('乙')),
  ]
  assert.equals(special.Match(rules, ['a', 'b', 'b']), {replay: ['a', 'b'], pending: ['b']})
  assert.equals(special.Match(rules, ['a', 'b', 'd']).output.text, '乙')
  assert.equals(special.Match(rules, ['a', 'b', 'd']).replay, ['a'])
}

suite.key_tokens_are_not_split_into_characters = (): void => {
  const rules = [special.Rule.new(['<C-x>', 'あ'], output_pattern.Parse('か\**ける'))]
  assert.equals(special.Match(rules, ['<C-x>']), {replay: [], pending: ['<C-x>']})
  const result = special.Match(rules, ['<C-x>', 'あ'])
  assert.equals(result.output.text, 'か*ける')
  assert.equals(result.output.boundary, 2)
}

suite.empty_input_and_no_rules = (): void => {
  assert.equals(special.Match([], []), {replay: [], pending: []})
  assert.equals(special.Match([], ['a']), {replay: ['a'], pending: []})
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
