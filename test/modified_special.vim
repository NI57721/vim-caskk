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
    assert.equals(special.Compose(pattern, events), {start_conversion: starts, reading: reading, okuri: okuri})
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
    assert.equals(special.Compose(pattern, events, true), {start_conversion: false, reading: reading, okuri: okuri})
  endfor
}

suite.one_key_special_has_no_later_modified_key = (): void => {
  assert.equals(special.Compose(output_pattern.Parse('か*ける'), [input.Event.new('<C-x>', true)]),
    {start_conversion: true, reading: 'かける', okuri: ''})
}

suite.modified_input_without_boundary = (): void => {
  assert.equals(special.Compose(output_pattern.Parse('かな'), [input.Event.new('1', true), input.Event.new('2', true)]),
    {start_conversion: true, reading: 'かな', okuri: ''})
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
  assert.equals(special.Compose(matched.output, matched.events),
    {start_conversion: true, reading: 'かな', okuri: ''})
}

suite.suffix_match_excludes_replayed_modified_input = (): void => {
  const rules = [special.Rule.new(['b', 'c'], output_pattern.Parse('か*ける'))]
  const events = [input.Event.new('a', true), input.Event.new('b'), input.Event.new('c', true)]
  const result = special.MatchEvents(rules, events)
  assert.equals(result.replay, [events[0]])
  assert.equals(special.Compose(result.output, result.events),
    {start_conversion: false, reading: 'かける', okuri: ''})
}

suite.matcher_handles_empty_input_and_full_replay = (): void => {
  assert.equals(special.MatchEvents([], []), {replay: [], pending: []})
  const event = input.Event.new('<C-x>', true)
  assert.equals(special.MatchEvents([], [event]), {replay: [event], pending: []})
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
