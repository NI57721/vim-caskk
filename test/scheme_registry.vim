vim9script

import 'caskk/input.vim' as input
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/scheme/registry.vim' as registry
import autoload 'caskk/composer.vim' as composer
import autoload 'caskk/composer/combination.vim' as combination

final suite = themis#suite('input scheme registry')
const assert = themis#helper('assert')

suite.register_compiles_normal_rules_and_specials = (): void => {
  const schemes = registry.Registry.new()
  schemes.Register('custom', {k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['k', 'a'], 'か*ける'),
  ])
  const compiled = schemes.Get('custom')
  assert.equals(combination.ComposeKeys(compiled.table, 'k', 'a'), {reading: 'か', okuri: ''})
  assert.equals(len(compiled.specials), 1)
  assert.equals(compiled.specials[0].keys, ['k', 'a'])
  assert.equals(compiled.specials[0].output.text, 'かける')
  assert.equals(compiled.specials[0].output.boundary, 1)
}

suite.schemes_are_selected_by_name = (): void => {
  const schemes = registry.Registry.new()
  schemes.Register('first', {k: 'k'}, {a: 'a'})
  schemes.Register('second', {k: 'n'}, {a: 'a'})
  assert.equals(combination.ComposeKeys(schemes.Get('first').table, 'k', 'a'),
    {reading: 'か', okuri: ''})
  assert.equals(combination.ComposeKeys(schemes.Get('second').table, 'k', 'a'),
    {reading: 'な', okuri: ''})
}

suite.unknown_name_is_rejected = (): void => {
  const schemes = registry.Registry.new()
  var caught = ''
  try
    schemes.Get('missing')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: unknown input scheme: missing')
}

suite.registries_do_not_share_registered_schemes = (): void => {
  const first = registry.Registry.new()
  const second = registry.Registry.new()
  first.Register('custom', {k: 'k'}, {a: 'a'})
  second.Register('custom', {k: 'n'}, {a: 'a'})
  assert.equals(combination.ComposeKeys(first.Get('custom').table, 'k', 'a'),
    {reading: 'か', okuri: ''})
  assert.equals(combination.ComposeKeys(second.Get('custom').table, 'k', 'a'),
    {reading: 'な', okuri: ''})
}

suite.reregistering_preserves_existing_composer_and_pending_input = (): void => {
  const schemes = registry.Registry.new()
  schemes.Register('custom', {k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['k', 'a'], '以前'),
  ])
  const existing = composer.Composer.new(schemes.Get('custom'))
  const first = input.Event.new('k')
  assert.equals(existing.Feed(first), [])
  schemes.Register('custom', {k: 'n'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['k', 'a'], '更新'),
  ])
  const current = composer.Composer.new(schemes.Get('custom'))
  assert.equals(existing.Pending(), [first])
  assert.equals(current.Feed(first), [])
  const second = input.Event.new('a')
  const previous_results = existing.Feed(second)
  const current_results = current.Feed(second)
  assert.equals(len(previous_results), 1)
  assert.equals(previous_results[0].output.text, '以前')
  assert.equals(len(current_results), 1)
  assert.equals(current_results[0].output.text, '更新')
  assert.equals(combination.ComposeKeys(schemes.Get('custom').table, 'k', 'a'),
    {reading: 'な', okuri: ''})
}

suite.invalid_registration_does_not_create_an_entry = (): void => {
  const schemes = registry.Registry.new()
  var compile_error = ''
  try
    schemes.Register('invalid', {}, {}, [scheme.SpecialDefinition.new(['a'], 'か*け*る')])
  catch
    compile_error = v:exception
  endtry
  assert.equals(compile_error, 'caskk: output pattern contains multiple latent okuri boundaries')
  var lookup_error = ''
  try
    schemes.Get('invalid')
  catch
    lookup_error = v:exception
  endtry
  assert.equals(lookup_error, 'caskk: unknown input scheme: invalid')
}

suite.failed_reregistration_preserves_previous_definition = (): void => {
  const schemes = registry.Registry.new()
  schemes.Register('custom', {k: 'k'}, {a: 'a'})
  var caught = ''
  try
    schemes.Register('custom', {k: 'n'}, {a: 'a**'})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: output pattern contains multiple latent okuri boundaries')
  assert.equals(combination.ComposeKeys(schemes.Get('custom').table, 'k', 'a'),
    {reading: 'か', okuri: ''})
}

suite.registration_does_not_retain_source_containers = (): void => {
  const schemes = registry.Registry.new()
  final consonants = {k: 'k'}
  final combinations = {a: 'a'}
  final specials = [scheme.SpecialDefinition.new(['k', 'a'], '特別')]
  schemes.Register('custom', consonants, combinations, specials)
  consonants.k = 'n'
  combinations.a = 'i'
  specials[0] = scheme.SpecialDefinition.new(['x'], '変更')
  const compiled = schemes.Get('custom')
  assert.equals(combination.ComposeKeys(compiled.table, 'k', 'a'), {reading: 'か', okuri: ''})
  assert.equals(compiled.specials[0].keys, ['k', 'a'])
  assert.equals(compiled.specials[0].output.text, '特別')
}
