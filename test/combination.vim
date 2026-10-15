vim9script

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
