vim9script

import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/composer/combination.vim' as combination

final suite = themis#suite('combination scheme')
const assert = themis#helper('assert')

suite.definition_keys_resolve_to_outputs = (): void => {
  const table = scheme.Compile({k: 'k', n: 'n', v: 'ky'}, {a: 'a', l: 'o*N', m: 'a*iN'})
  assert.equals(combination.ComposeKeys(table, 'k', 'a'), {reading: 'か', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'k', 'l'), {reading: 'こん', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'n', 'm'), {reading: 'ないん', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'v', 'l'), {reading: 'きょん', okuri: ''})
}

suite.okuri_input_uses_compiled_boundary = (): void => {
  const table = scheme.Compile({k: 'k', v: 'ky'}, {a: 'a', l: 'o*N'})
  assert.equals(combination.ComposeKeys(table, 'k', 'l', true), {reading: 'こ', okuri: 'ん'})
  assert.equals(combination.ComposeKeys(table, 'v', 'l', true), {reading: 'きょ', okuri: 'ん'})
  assert.equals(combination.ComposeKeys(table, 'k', 'a', true), {reading: 'か', okuri: ''})
}

suite.small_tsu_and_kana_boundary_edges = (): void => {
  const table = scheme.Compile({j: 'ky'}, {l: 'aTi', a: '*a', o: 'o*'})
  assert.equals(combination.ComposeKeys(table, 'j', 'l'), {reading: 'きゃっい', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'j', 'a', true), {reading: '', okuri: 'きゃ'})
  assert.equals(combination.ComposeKeys(table, 'j', 'o', true), {reading: 'きょ', okuri: ''})
}

suite.small_kana_and_palatalized_i = (): void => {
  const table = scheme.Compile({j: 'ky', c: 'x', y: 'xy', w: 'xw'}, {a: 'a', i: 'i*iN'})
  assert.equals(combination.ComposeKeys(table, 'j', 'i', true), {reading: 'き', okuri: 'いん'})
  assert.equals(combination.ComposeKeys(table, 'c', 'a'), {reading: 'ぁ', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'y', 'a'), {reading: 'ゃ', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'w', 'a'), {reading: 'ゎ', okuri: ''})
}

suite.key_tokens_are_opaque = (): void => {
  const table = scheme.Compile({'1': 'k', '<M-j>': 'n'}, {'<C-x>': 'ei'})
  assert.equals(combination.ComposeKeys(table, '1', '<C-x>'), {reading: 'けい', okuri: ''})
  assert.equals(combination.ComposeKeys(table, '<M-j>', '<C-x>'), {reading: 'ねい', okuri: ''})
}

suite.patterns_are_decoded_at_compile_time = (): void => {
  const table = scheme.Compile({k: 'k'}, {l: 'a\**i\\N'})
  assert.equals(table.combinations.l.text, 'a*i\N')
  assert.equals(table.combinations.l.boundary, 2)
  assert.equals(combination.ComposeKeys(table, 'k', 'l', true), {reading: 'か*', okuri: 'い\ん'})
}

suite.source_definitions_remain_independent = (): void => {
  final consonants = {k: 'k'}
  final combinations = {l: 'o*N'}
  const table = scheme.Compile(consonants, combinations)
  consonants.k = 'n'
  combinations.l = 'a'
  assert.equals(combination.ComposeKeys(table, 'k', 'l', true), {reading: 'こ', okuri: 'ん'})
  assert.equals(consonants.k, 'n')
  assert.equals(combinations.l, 'a')
}

suite.independent_schemes = (): void => {
  const first = scheme.Compile({k: 'k'}, {l: 'o*N'})
  const second = scheme.Compile({k: 'n'}, {l: 'a*iN'})
  assert.equals(combination.ComposeKeys(first, 'k', 'l', true), {reading: 'こ', okuri: 'ん'})
  assert.equals(combination.ComposeKeys(second, 'k', 'l', true), {reading: 'な', okuri: 'いん'})
}

suite.empty_definitions_and_outputs = (): void => {
  const empty = scheme.Compile({}, {})
  assert.equals(empty.consonants, {})
  assert.equals(empty.combinations, {})
  const table = scheme.Compile({k: ''}, {a: ''})
  assert.equals(combination.ComposeKeys(table, 'k', 'a'), {reading: '', okuri: ''})
}

suite.invalid_pattern_is_rejected_at_compile_time = (): void => {
  var caught = ''
  try
    scheme.Compile({k: 'k'}, {l: 'o*N*'})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: output pattern contains multiple latent okuri boundaries')
}

suite.unknown_keys_are_rejected = (): void => {
  const table = scheme.Compile({k: 'k'}, {a: 'a'})
  var caught = ''
  try
    combination.ComposeKeys(table, 'x', 'a')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: unknown consonant key: x')
  caught = ''
  try
    combination.ComposeKeys(table, 'k', 'x')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: unknown combination key: x')
}
