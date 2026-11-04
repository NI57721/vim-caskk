vim9script

import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/composer/combination.vim' as combination

final suite = themis#suite('input scheme')
const assert = themis#helper('assert')

suite.definition_keys_resolve_to_outputs = (): void => {
  const table = scheme.Compile({k: 'k', n: 'n', v: 'ky'}, {a: 'a', l: 'o*N', m: 'a*iN'}).table
  assert.equals(combination.ComposeKeys(table, 'k', 'a'), {reading: 'か', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'k', 'l'), {reading: 'こん', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'n', 'm'), {reading: 'ないん', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'v', 'l'), {reading: 'きょん', okuri: ''})
}

suite.okuri_input_uses_compiled_boundary = (): void => {
  const table = scheme.Compile({k: 'k', v: 'ky'}, {a: 'a', l: 'o*N'}).table
  assert.equals(combination.ComposeKeys(table, 'k', 'l', true), {reading: 'こ', okuri: 'ん'})
  assert.equals(combination.ComposeKeys(table, 'v', 'l', true), {reading: 'きょ', okuri: 'ん'})
  assert.equals(combination.ComposeKeys(table, 'k', 'a', true), {reading: 'か', okuri: ''})
}

suite.small_tsu_and_kana_boundary_edges = (): void => {
  const table = scheme.Compile({j: 'ky'}, {l: 'aTi', o: 'o*'}).table
  assert.equals(combination.ComposeKeys(table, 'j', 'l'), {reading: 'きゃっい', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'j', 'o', true), {reading: 'きょ', okuri: ''})
}

suite.small_kana_and_palatalized_i = (): void => {
  const table = scheme.Compile({j: 'ky', c: 'x', y: 'xy', w: 'xw'}, {a: 'a', i: 'i*iN'}).table
  assert.equals(combination.ComposeKeys(table, 'j', 'i', true), {reading: 'き', okuri: 'いん'})
  assert.equals(combination.ComposeKeys(table, 'c', 'a'), {reading: 'ぁ', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'y', 'a'), {reading: 'ゃ', okuri: ''})
  assert.equals(combination.ComposeKeys(table, 'w', 'a'), {reading: 'ゎ', okuri: ''})
}

suite.key_tokens_are_opaque = (): void => {
  const table = scheme.Compile({'1': 'k', '<M-j>': 'n'}, {'<C-x>': 'ei'}).table
  assert.equals(combination.ComposeKeys(table, '1', '<C-x>'), {reading: 'けい', okuri: ''})
  assert.equals(combination.ComposeKeys(table, '<M-j>', '<C-x>'), {reading: 'ねい', okuri: ''})
}

suite.input_key_strings_distinguish_vim_keycodes_from_literal_angle_text = (): void => {
  assert.equals(scheme.InputKeys("\<C-K>"), ['<C-K>'])
  assert.equals(scheme.InputKeys('<C-K>'), ['<', 'c', '-', 'k', '>'])
  assert.equals(scheme.InputKeys('\<C-K>'), ['\', '<', 'c', '-', 'k', '>'])
}

suite.patterns_are_decoded_at_compile_time = (): void => {
  const table = scheme.Compile({k: 'k'}, {l: 'a\**i\\N'}).table
  assert.equals(table.combinations.l.text, 'a*i\N')
  assert.equals(table.combinations.l.boundary, 2)
  assert.equals(combination.ComposeKeys(table, 'k', 'l', true), {reading: 'か*', okuri: 'い\ん'})
}

suite.source_definitions_remain_independent = (): void => {
  final consonants = {k: 'k'}
  final combinations = {l: 'o*N'}
  const table = scheme.Compile(consonants, combinations).table
  consonants.k = 'n'
  combinations.l = 'a'
  assert.equals(combination.ComposeKeys(table, 'k', 'l', true), {reading: 'こ', okuri: 'ん'})
  assert.equals(consonants.k, 'n')
  assert.equals(combinations.l, 'a')
}

suite.independent_schemes = (): void => {
  const first = scheme.Compile({k: 'k'}, {l: 'o*N'}).table
  const second = scheme.Compile({k: 'n'}, {l: 'a*iN'}).table
  assert.equals(combination.ComposeKeys(first, 'k', 'l', true), {reading: 'こ', okuri: 'ん'})
  assert.equals(combination.ComposeKeys(second, 'k', 'l', true), {reading: 'な', okuri: 'いん'})
}

suite.empty_definitions_and_outputs = (): void => {
  const empty = scheme.Compile({}, {}).table
  assert.equals(empty.consonants, {})
  assert.equals(empty.combinations, {})
  const table = scheme.Compile({k: ''}, {a: ''}).table
  assert.equals(combination.ComposeKeys(table, 'k', 'a'), {reading: '', okuri: ''})
}

suite.nasal_and_sokuon_are_stored_as_output_symbols_not_consonant_rows = (): void => {
  const compiled = scheme.Compile({q: 'N', l: 'T'}, {})
  assert.equals(compiled.table.consonants, {})
  assert.equals(compiled.table.symbols, {q: 'ん', l: 'っ'})
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

suite.combination_cannot_start_with_okuri_boundary = (): void => {
  var caught = ''
  try
    scheme.Compile({k: 'k'}, {q: '*a'})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: combination output cannot start with latent okuri boundary')
}

suite.unknown_keys_are_rejected = (): void => {
  const table = scheme.Compile({k: 'k'}, {a: 'a'}).table
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

suite.specials_are_compiled_with_normal_combinations = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['k', 'a'], '特別'),
  ])
  assert.equals(combination.ComposeKeys(compiled.table, 'k', 'a'), {reading: 'か', okuri: ''})
  assert.equals(len(compiled.specials), 1)
  assert.equals(compiled.specials[0].keys, ['k', 'a'])
  assert.equals(compiled.specials[0].output.text, '特別')
  assert.equals(compiled.specials[0].output.boundary, -1)
}

suite.special_patterns_are_decoded_at_compile_time = (): void => {
  const compiled = scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['<C-x>', 'あ'], 'か\**ける\\尾'),
  ])
  assert.equals(compiled.specials[0].keys, ['<C-x>', 'あ'])
  assert.equals(compiled.specials[0].output.text, 'か*ける\尾')
  assert.equals(compiled.specials[0].output.boundary, 2)
}

suite.special_outputs_are_literal_text_without_kana_generation = (): void => {
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['a'], 'aNT')])
  assert.equals(compiled.specials[0].output.text, 'aNT')
}

suite.specials_can_be_omitted = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'})
  assert.equals(compiled.specials, [])
  assert.equals(combination.ComposeKeys(compiled.table, 'k', 'a'), {reading: 'か', okuri: ''})
}

suite.empty_special_output_is_preserved = (): void => {
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['a'], '')])
  assert.equals(len(compiled.specials), 1)
  assert.equals(compiled.specials[0].output.text, '')
  assert.equals(compiled.specials[0].output.boundary, -1)
}

suite.compiled_specials_do_not_retain_source_containers = (): void => {
  final keys = ['k', 'a']
  final definitions = [scheme.SpecialDefinition.new(keys, '特別')]
  const compiled = scheme.Compile({}, {}, definitions)
  keys[0] = 'n'
  definitions[0] = scheme.SpecialDefinition.new(['x'], '変更')
  definitions->add(scheme.SpecialDefinition.new(['y'], '追加'))
  assert.equals(len(compiled.specials), 1)
  assert.equals(compiled.specials[0].keys, ['k', 'a'])
  assert.equals(compiled.specials[0].output.text, '特別')
  assert.equals(keys, ['n', 'a'])
  assert.equals(len(definitions), 2)
}

suite.compiled_specials_are_independent_between_schemes = (): void => {
  const first = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['a'], '甲')])
  const second = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['a'], '乙')])
  assert.equals(first.specials[0].output.text, '甲')
  assert.equals(second.specials[0].output.text, '乙')
}

suite.invalid_special_pattern_is_rejected_at_compile_time = (): void => {
  var caught = ''
  try
    scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['a'], 'か*け*る')])
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: output pattern contains multiple latent okuri boundaries')
}

suite.empty_special_keys_are_rejected_at_compile_time = (): void => {
  var caught = ''
  try
    scheme.Compile({}, {}, [scheme.SpecialDefinition.new([], 'かな')])
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: special requires at least one key')
}
