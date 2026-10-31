vim9script

import 'caskk/input.vim' as input
import autoload 'caskk/scheme/output_pattern.vim' as output_pattern
import autoload 'caskk/composer/combination.vim' as combination

final suite = themis#suite('combination composition')
const assert = themis#helper('assert')

suite.ordinary_input = (): void => {
  assert.equals(combination.Compose('k', output_pattern.Parse('a')),
    {reading: 'ka', okuri: ''})
  assert.equals(combination.Compose('k', output_pattern.Parse('o*n')),
    {reading: 'kon', okuri: ''})
  assert.equals(combination.Compose('n', output_pattern.Parse('a*in')),
    {reading: 'nain', okuri: ''})
}

suite.okuri_input_activates_boundary = (): void => {
  assert.equals(combination.Compose('k', output_pattern.Parse('o*n'), true),
    {reading: 'ko', okuri: 'n'})
  assert.equals(combination.Compose('n', output_pattern.Parse('a*in'), true),
    {reading: 'na', okuri: 'in'})
}

suite.okuri_input_without_boundary = (): void => {
  assert.equals(combination.Compose('k', output_pattern.Parse('a'), true),
    {reading: 'ka', okuri: ''})
}

suite.multicharacter_consonant = (): void => {
  assert.equals(combination.Compose('ky', output_pattern.Parse('o*n')),
    {reading: 'kyon', okuri: ''})
  assert.equals(combination.Compose('ky', output_pattern.Parse('o*n'), true),
    {reading: 'kyo', okuri: 'n'})
}

suite.escaped_literals_are_preserved = (): void => {
  assert.equals(combination.Compose('k', output_pattern.Parse('a\*in'), true),
    {reading: 'ka*in', okuri: ''})
  assert.equals(combination.Compose('k', output_pattern.Parse('a\**i\\n'), true),
    {reading: 'ka*', okuri: 'i\n'})
}

suite.unicode_boundary_uses_character_offset = (): void => {
  assert.equals(combination.Compose('前', output_pattern.Parse('た*べ'), true),
    {reading: '前た', okuri: 'べ'})
  assert.equals(combination.Compose('', output_pattern.Parse("か\u3099*く"), true),
    {reading: "か\u3099", okuri: 'く'})
}

suite.boundary_at_edges = (): void => {
  assert.equals(combination.Compose('k', output_pattern.Parse('*a'), true),
    {reading: 'k', okuri: 'a'})
  assert.equals(combination.Compose('k', output_pattern.Parse('a*'), true),
    {reading: 'ka', okuri: ''})
  assert.equals(combination.Compose('k', output_pattern.Parse('*'), true),
    {reading: 'k', okuri: ''})
}

suite.empty_output = (): void => {
  assert.equals(combination.Compose('k', output_pattern.Parse('')),
    {reading: 'k', okuri: ''})
  assert.equals(combination.Compose('', output_pattern.Parse(''), true),
    {reading: '', okuri: ''})
}

suite.consonant_is_literal_text = (): void => {
  assert.equals(combination.Compose('*\', output_pattern.Parse('a*in'), true),
    {reading: '*\a', okuri: 'in'})
}

suite.parsed_pattern_can_be_reused = (): void => {
  const pattern = output_pattern.Parse('o*n')
  assert.equals(combination.Compose('k', pattern, true), {reading: 'ko', okuri: 'n'})
  assert.equals(combination.Compose('n', pattern), {reading: 'non', okuri: ''})
  assert.equals(pattern.text, 'on')
  assert.equals(pattern.boundary, 1)
}

suite.modified_events_use_the_current_preedit_context = (): void => {
  const pattern = output_pattern.Parse('こ*ん')
  for [preedit, first, second, starts, reading, okuri, boundary] in [
    [false, false, false, false, 'こん', '', false],
    [false, false, true, true, 'こ', 'ん', true],
    [false, true, false, true, 'こん', '', false],
    [false, true, true, true, 'こ', 'ん', true],
    [true, false, false, false, 'こん', '', false],
    [true, true, false, false, '', 'こん', true],
    [true, false, true, false, 'こ', 'ん', true],
    [true, true, true, false, '', 'こん', true],
  ]
    const events = [input.Event.new('k', first), input.Event.new('l', second)]
    const composed = combination.ComposeEvents(pattern, events, preedit)
    assert.equals(composed.start_conversion, starts)
    assert.equals(composed.reading, reading)
    assert.equals(composed.okuri, okuri)
    assert.equals(composed.okuri_started, boundary)
  endfor
}

suite.modified_consonant_starts_okuri_without_a_latent_marker = (): void => {
  const events = [input.Event.new('j', true), input.Event.new('i')]
  const composed = combination.ComposeEvents(output_pattern.Parse('じ'), events, true)
  assert.equals(composed.start_conversion, false)
  assert.equals(composed.reading, '')
  assert.equals(composed.okuri, 'じ')
  assert.equals(composed.okuri_started, true)
}

suite.modified_combination_without_latent_marker_preserves_reading = (): void => {
  const events = [input.Event.new('k'), input.Event.new('a', true)]
  const composed = combination.ComposeEvents(output_pattern.Parse('か'), events, true)
  assert.equals(composed.reading, 'か')
  assert.equals(composed.okuri, '')
  assert.equals(composed.okuri_started, false)
}

suite.event_composition_requires_a_consonant_and_a_combination = (): void => {
  const event = input.Event.new('a')
  for events in [[], [event], [event, event, event]]
    var caught = ''
    try
      combination.ComposeEvents(output_pattern.Parse('かな'), events)
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: combination composition requires exactly two input events')
  endfor
}
