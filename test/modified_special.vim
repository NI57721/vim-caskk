vim9script

import 'caskk/input.vim' as input
import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme/output_pattern.vim' as output_pattern

final suite = themis#suite('modified specials')
const assert = themis#helper('assert')

suite.modified_semantics_outside_preedit = (): void => {
  const pattern = output_pattern.Parse('か*ける')
  # first, second, third, start conversion, reading, okuri
  for [first, second, third, starts, reading, okuri] in [
    [false, false, false, false, 'かける', ''],
    [true, false, false, true, 'かける', ''],
    [true, true, false, true, 'か', 'ける'],
    [true, false, true, true, 'か', 'ける'],
    [true, true, true, true, 'か', 'ける'],
    [false, true, false, false, 'かける', ''],
    [false, false, true, false, 'かける', ''],
    [false, true, true, false, 'かける', ''],
  ]
    const events = [input.Event.new('a', first), input.Event.new('b', second), input.Event.new('c', third)]
    const composed = special.Compose(pattern, events)
    assert.equals(composed.start_conversion, starts)
    assert.equals(composed.reading, reading)
    assert.equals(composed.okuri, okuri)
  endfor
}

suite.modified_semantics_in_preedit = (): void => {
  const pattern = output_pattern.Parse('か*ける')
  for [first, second, third, reading, okuri] in [
    [false, false, false, 'かける', ''],
    [true, false, false, 'かける', ''],
    [false, true, false, 'か', 'ける'],
    [false, false, true, 'か', 'ける'],
    [false, true, true, 'か', 'ける'],
    [true, true, false, 'か', 'ける'],
    [true, false, true, 'か', 'ける'],
    [true, true, true, 'か', 'ける'],
  ]
    const events = [input.Event.new('a', first), input.Event.new('b', second), input.Event.new('c', third)]
    const composed = special.Compose(pattern, events, true)
    assert.equals(composed.start_conversion, false)
    assert.equals(composed.reading, reading)
    assert.equals(composed.okuri, okuri)
  endfor
}

suite.one_key_special_has_no_later_modified_key = (): void => {
  const composed = special.Compose(output_pattern.Parse('か*ける'), [input.Event.new('<C-x>', true)])
  assert.equals(composed.start_conversion, true)
  assert.equals(composed.reading, 'かける')
  assert.equals(composed.okuri, '')
}

suite.modified_input_without_boundary = (): void => {
  const composed = special.Compose(output_pattern.Parse('かな'), [input.Event.new('1', true), input.Event.new('2', true)])
  assert.equals(composed.start_conversion, true)
  assert.equals(composed.reading, 'かな')
  assert.equals(composed.okuri, '')
}

suite.matcher_preserves_modified_events_in_pending_and_replay = (): void => {
  const rules = [special.Rule.new(['a', 'b'], output_pattern.Parse('かな'))]
  const first = input.Event.new('x', true)
  const second = input.Event.new('a', true)
  const result = special.MatchEvents(rules, [first, second])
  assert.equals(result.replay, [first])
  assert.equals(result.pending, [second])
  const matched = special.MatchEvents(rules, result.pending + [input.Event.new('b')])
  assert.equals(matched.output.text, 'かな')
  assert.equals(matched.events[0].key, 'a')
  assert.equals(matched.events[0].modified, true)
  assert.equals(matched.events[1].modified, false)
  const composed = special.Compose(matched.output, matched.events)
  assert.equals(composed.start_conversion, true)
  assert.equals(composed.reading, 'かな')
  assert.equals(composed.okuri, '')
}

suite.suffix_match_excludes_replayed_modified_input = (): void => {
  const rules = [special.Rule.new(['b', 'c'], output_pattern.Parse('か*ける'))]
  const events = [input.Event.new('a', true), input.Event.new('b'), input.Event.new('c', true)]
  const result = special.MatchEvents(rules, events)
  assert.equals(result.replay, [events[0]])
  const composed = special.Compose(result.output, result.events)
  assert.equals(composed.start_conversion, false)
  assert.equals(composed.reading, 'かける')
  assert.equals(composed.okuri, '')
}

suite.matcher_handles_empty_input_and_full_replay = (): void => {
  const match = special.MatchEvents([], [])
  assert.equals(match.replay, [])
  assert.equals(match.pending, [])
  assert.equals(match.output is null_object, true)
  assert.equals(match.events, [])
  const event = input.Event.new('<C-x>', true)
  const next_match = special.MatchEvents([], [event])
  assert.equals(next_match.replay, [event])
  assert.equals(next_match.pending, [])
  assert.equals(next_match.output is null_object, true)
  assert.equals(next_match.events, [])
}

suite.empty_events_cannot_compose_a_special = (): void => {
  var caught = ''
  try
    special.Compose(output_pattern.Parse('かな'), [])
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: special composition requires at least one input event')
}

suite.fallback_separates_replay_matched_events_and_remaining_events = (): void => {
  const rules = [
    special.Rule.new(['a', 'b'], output_pattern.Parse('か*ける')),
    special.Rule.new(['a', 'b', 'c', 'd'], output_pattern.Parse('長')),
  ]
  const preceding = input.Event.new('!')
  const first = input.Event.new('a', true)
  const second = input.Event.new('b')
  const rest = input.Event.new('x', true)
  const result = special.MatchEvents(rules, [preceding, first, second, rest])
  assert.equals(result.replay, [preceding])
  assert.equals(result.pending, [])
  assert.equals(result.events, [first, second])
  assert.equals(result.rest, [rest])
  assert.equals(result.output.text, 'かける')
  const composed = special.Compose(result.output, result.events)
  assert.equals(composed.start_conversion, true)
  assert.equals(composed.reading, 'かける')
  assert.equals(composed.okuri, '')
}
