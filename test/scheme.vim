vim9script

import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/composer.vim' as composer
import 'caskk/input.vim' as input
import 'caskk/combination_table.vim' as table_types

final suite = themis#suite('input scheme')
const assert = themis#helper('assert')

# Isolate the compiled combination table while using the live event pipeline.
def ComposeInput(table: table_types.CombinationTable, consonant: string,
    combination_key: string, modified: bool = false): dict<string>
  const engine = composer.Composer.new(scheme.CompiledScheme.new(table, []))
  engine.Feed(input.Event.new(consonant))
  const results = engine.Feed(input.Event.new(combination_key, modified))
  const result = composer.Compose(results[0])
  return {reading: result.reading, okuri: result.okuri}
enddef

suite.definition_keys_resolve_to_outputs = (): void => {
  const table = scheme.Compile({k: 'k', n: 'n', v: 'ky'}, {a: 'a', l: 'o*N', m: 'a*iN'}).table
  assert.equals(ComposeInput(table, 'k', 'a'), {reading: 'か', okuri: ''})
  assert.equals(ComposeInput(table, 'k', 'l'), {reading: 'こん', okuri: ''})
  assert.equals(ComposeInput(table, 'n', 'm'), {reading: 'ないん', okuri: ''})
  assert.equals(ComposeInput(table, 'v', 'l'), {reading: 'きょん', okuri: ''})
}

suite.okuri_input_uses_compiled_boundary = (): void => {
  const table = scheme.Compile({k: 'k', v: 'ky'}, {a: 'a', l: 'o*N'}).table
  assert.equals(ComposeInput(table, 'k', 'l', true), {reading: 'こ', okuri: 'ん'})
  assert.equals(ComposeInput(table, 'v', 'l', true), {reading: 'きょ', okuri: 'ん'})
  assert.equals(ComposeInput(table, 'k', 'a', true), {reading: 'か', okuri: ''})
}

suite.small_tsu_and_kana_boundary_edges = (): void => {
  const table = scheme.Compile({j: 'ky'}, {l: 'aTi', o: 'o*'}).table
  assert.equals(ComposeInput(table, 'j', 'l'), {reading: 'きゃっい', okuri: ''})
  assert.equals(ComposeInput(table, 'j', 'o', true), {reading: 'きょ', okuri: ''})
}

suite.small_kana_and_palatalized_i = (): void => {
  const table = scheme.Compile({j: 'ky', c: 'x', y: 'xy', w: 'xw'}, {a: 'a', i: 'i*iN'}).table
  assert.equals(ComposeInput(table, 'j', 'i', true), {reading: 'き', okuri: 'いん'})
  assert.equals(ComposeInput(table, 'c', 'a'), {reading: 'ぁ', okuri: ''})
  assert.equals(ComposeInput(table, 'y', 'a'), {reading: 'ゃ', okuri: ''})
  assert.equals(ComposeInput(table, 'w', 'a'), {reading: 'ゎ', okuri: ''})
}

suite.key_tokens_are_opaque = (): void => {
  const table = scheme.Compile(
    scheme.ValidateConsonants({'1': 'k', "\<M-j>": 'n'}),
    scheme.ValidateCombinations({"\<C-X>": 'ei'})).table
  assert.equals(ComposeInput(table, '1', '<C-X>'), {reading: 'けい', okuri: ''})
  assert.equals(ComposeInput(table, scheme.ConsonantKeys("\<M-j>")[0], '<C-X>'), {reading: 'ねい', okuri: ''})
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
  assert.equals(ComposeInput(table, 'k', 'l', true), {reading: 'か*', okuri: 'い\ん'})
}

suite.source_definitions_remain_independent = (): void => {
  final consonants = {k: 'k'}
  final combinations = {l: 'o*N'}
  const table = scheme.Compile(consonants, combinations).table
  consonants.k = 'n'
  combinations.l = 'a'
  assert.equals(ComposeInput(table, 'k', 'l', true), {reading: 'こ', okuri: 'ん'})
  assert.equals(consonants.k, 'n')
  assert.equals(combinations.l, 'a')
}

suite.independent_schemes = (): void => {
  const first = scheme.Compile({k: 'k'}, {l: 'o*N'}).table
  const second = scheme.Compile({k: 'n'}, {l: 'a*iN'}).table
  assert.equals(ComposeInput(first, 'k', 'l', true), {reading: 'こ', okuri: 'ん'})
  assert.equals(ComposeInput(second, 'k', 'l', true), {reading: 'な', okuri: 'いん'})
}

suite.empty_definitions_and_outputs = (): void => {
  const empty = scheme.Compile({}, {}).table
  assert.equals(empty.consonants, {})
  assert.equals(empty.combinations, {})
  const table = scheme.Compile({k: ''}, {a: ''}).table
  assert.equals(ComposeInput(table, 'k', 'a'), {reading: '', okuri: ''})
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

suite.unknown_keys_are_returned_for_normal_fallback = (): void => {
  for keys in [['x', 'a'], ['k', 'x']]
    const engine = composer.Composer.new(scheme.Compile({k: 'k'}, {a: 'a'}))
    final results: list<composer.Result> = []
    for key in keys
      results->extend(engine.Feed(input.Event.new(key)))
    endfor
    if keys[0] ==# 'x'
      assert.equals(results[0].output is null_object, true)
      assert.equals(results[0].events[0].key, 'x')
      assert.equals(results[1].output.text, 'あ')
    else
      assert.equals(mapnew(results, (_, result) => result.output is null_object), [true, true])
      assert.equals(mapnew(results, (_, result) => result.events[0].key), ['k', 'x'])
    endif
  endfor
}

suite.specials_are_compiled_with_normal_combinations = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['k', 'a'], '特別'),
  ])
  assert.equals(ComposeInput(compiled.table, 'k', 'a'), {reading: 'か', okuri: ''})
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
  assert.equals(ComposeInput(compiled.table, 'k', 'a'), {reading: 'か', okuri: ''})
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
