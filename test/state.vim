vim9script

import 'caskk/input.vim' as input
import 'caskk/composition.vim' as composition
import autoload 'caskk/state.vim' as state
import autoload 'caskk/composer.vim' as composer
import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/input/normalize.vim' as normalize
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/scheme/output_pattern.vim' as output_pattern

final suite = themis#suite('IME reading state')
const assert = themis#helper('assert')

suite.initial_state_is_direct = (): void => {
  const ime = state.State.new()
  assert.equals(ime.in_preedit, false)
  assert.equals(ime.reading, '')
  assert.equals(ime.okuri, '')
  assert.equals(ime.okuri_started, false)
}

suite.direct_input_is_returned_without_retaining_preedit = (): void => {
  const ime = state.State.new()
  const composed = special.Compose(output_pattern.Parse('か*ける'), [input.Event.new('a')])
  assert.equals(ime.Apply(composed), 'かける')
  assert.equals(ime.in_preedit, false)
  assert.equals(ime.reading, '')
  assert.equals(ime.okuri, '')
  assert.equals(ime.okuri_started, false)
}

suite.modified_first_input_starts_preedit = (): void => {
  const ime = state.State.new()
  const composed = special.Compose(output_pattern.Parse('かな'), [input.Event.new('a', true)])
  assert.equals(ime.Apply(composed), '')
  assert.equals(ime.in_preedit, true)
  assert.equals(ime.reading, 'かな')
  assert.equals(ime.okuri, '')
}

suite.preedit_reading_accumulates_from_composed_readings = (): void => {
  const ime = state.State.new()
  assert.equals(ime.Apply(composition.Result.new(true, 'か', '', false)), '')
  assert.equals(ime.Apply(composition.Result.new(false, 'ん', '', false)), '')
  assert.equals(ime.Apply(composition.Result.new(false, 'じ', '', false)), '')
  assert.equals(ime.in_preedit, true)
  assert.equals(ime.reading, 'かんじ')
  assert.equals(ime.okuri, '')
}

suite.modified_special_starts_preedit_with_okuri = (): void => {
  const ime = state.State.new()
  const events = [input.Event.new('a', true), input.Event.new('b', true)]
  assert.equals(ime.Apply(special.Compose(output_pattern.Parse('か*ける'), events)), '')
  assert.equals(ime.in_preedit, true)
  assert.equals(ime.reading, 'か')
  assert.equals(ime.okuri, 'ける')
  assert.equals(ime.okuri_started, true)
}

suite.later_modified_input_activates_okuri_in_existing_preedit = (): void => {
  const ime = state.State.new()
  assert.equals(ime.Apply(special.Compose(output_pattern.Parse('お'), [input.Event.new('o', true)])), '')
  const events = [input.Event.new('a'), input.Event.new('b', true)]
  assert.equals(ime.Apply(special.Compose(output_pattern.Parse('く*る'), events, ime.in_preedit)), '')
  assert.equals(ime.reading, 'おく')
  assert.equals(ime.okuri, 'る')
  assert.equals(ime.okuri_started, true)
}

suite.input_after_okuri_boundary_extends_okuri = (): void => {
  const ime = state.State.new()
  const events = [input.Event.new('a', true), input.Event.new('b', true)]
  assert.equals(ime.Apply(special.Compose(output_pattern.Parse('か*け'), events)), '')
  const next = special.Compose(output_pattern.Parse('る'), [input.Event.new('c')], ime.in_preedit)
  assert.equals(ime.Apply(next), '')
  assert.equals(ime.reading, 'か')
  assert.equals(ime.okuri, 'ける')
  assert.equals(ime.okuri_started, true)
}

suite.trailing_boundary_is_retained_before_okuri_text_arrives = (): void => {
  const ime = state.State.new()
  const events = [input.Event.new('a', true), input.Event.new('b', true)]
  assert.equals(ime.Apply(special.Compose(output_pattern.Parse('た*'), events)), '')
  assert.equals(ime.reading, 'た')
  assert.equals(ime.okuri, '')
  assert.equals(ime.okuri_started, true)
  const next = special.Compose(output_pattern.Parse('べる'), [input.Event.new('c')], ime.in_preedit)
  assert.equals(ime.Apply(next), '')
  assert.equals(ime.reading, 'た')
  assert.equals(ime.okuri, 'べる')
}

suite.leading_boundary_allows_an_empty_reading = (): void => {
  const ime = state.State.new()
  const events = [input.Event.new('a', true), input.Event.new('b', true)]
  assert.equals(ime.Apply(special.Compose(output_pattern.Parse('*かな'), events)), '')
  assert.equals(ime.in_preedit, true)
  assert.equals(ime.reading, '')
  assert.equals(ime.okuri, 'かな')
  assert.equals(ime.okuri_started, true)
}

suite.commit_returns_reading_and_okuri_and_restores_direct_state = (): void => {
  const ime = state.State.new()
  const events = [input.Event.new('a', true), input.Event.new('b', true)]
  assert.equals(ime.Apply(special.Compose(output_pattern.Parse('か*ける'), events)), '')
  assert.equals(ime.Commit(), 'かける')
  assert.equals(ime.in_preedit, false)
  assert.equals(ime.reading, '')
  assert.equals(ime.okuri, '')
  assert.equals(ime.okuri_started, false)
  const next = special.Compose(output_pattern.Parse('かな'), [input.Event.new('a')])
  assert.equals(ime.Apply(next), 'かな')
}

suite.commit_in_direct_state_returns_no_text = (): void => {
  const ime = state.State.new()
  assert.equals(ime.Commit(), '')
  assert.equals(ime.in_preedit, false)
}

suite.empty_modified_output_still_starts_preedit = (): void => {
  const ime = state.State.new()
  assert.equals(ime.Apply(special.Compose(output_pattern.Parse(''), [input.Event.new('a', true)])), '')
  assert.equals(ime.in_preedit, true)
  assert.equals(ime.reading, '')
  assert.equals(ime.Commit(), '')
  assert.equals(ime.in_preedit, false)
}

suite.states_do_not_share_preedit = (): void => {
  const first = state.State.new()
  const second = state.State.new()
  assert.equals(first.Apply(special.Compose(output_pattern.Parse('かな'), [input.Event.new('a', true)])), '')
  assert.equals(second.in_preedit, false)
  assert.equals(second.reading, '')
  assert.equals(first.reading, 'かな')
}

suite.reprocessed_specials_use_state_updated_by_preceding_output = (): void => {
  const compiled = scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['a'], 'さ'),
    scheme.SpecialDefinition.new(['a', 'b', 'c', 'z'], '長'),
    scheme.SpecialDefinition.new(['b', 'c', 'x'], 'か*ける'),
  ])
  const engine = composer.Composer.new(compiled)
  const ime = state.State.new()
  for event in [input.Event.new('a', true), input.Event.new('b'), input.Event.new('c')]
    assert.equals(engine.Feed(event), [])
  endfor
  const results = engine.Feed(input.Event.new('x', true))
  assert.equals(len(results), 2)
  for result in results
    assert.equals(ime.Apply(composer.Compose(result, ime.in_preedit)), '')
  endfor
  assert.equals(ime.in_preedit, true)
  assert.equals(ime.reading, 'さか')
  assert.equals(ime.okuri, 'ける')
}

suite.uppercase_and_sticky_keys_produce_the_same_preedit = (): void => {
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['a', 'b', 'c'], 'か*ける')])
  for keys in [['A', 'B', 'c'], [';', 'a', ';', 'b', 'c']]
    const normalizer = normalize.Normalizer.new(';')
    const engine = composer.Composer.new(compiled)
    const ime = state.State.new()
    for key in keys
      for event in normalizer.Feed(key)
        for result in engine.Feed(event)
          assert.equals(ime.Apply(composer.Compose(result, ime.in_preedit)), '')
        endfor
      endfor
    endfor
    assert.equals(ime.in_preedit, true)
    assert.equals(ime.reading, 'か')
    assert.equals(ime.okuri, 'ける')
    assert.equals(ime.okuri_started, true)
  endfor
}

suite.modified_normal_consonant_begins_okuri_after_existing_reading = (): void => {
  const compiled = scheme.Compile({k: 'k', j: 'z'}, {l: 'aN', i: 'i'})
  for keys in [['K', 'l', 'J', 'i'], [';', 'k', 'l', ';', 'j', 'i']]
    const normalizer = normalize.Normalizer.new(';')
    const engine = composer.Composer.new(compiled)
    const ime = state.State.new()
    for key in keys
      for event in normalizer.Feed(key)
        for result in engine.Feed(event)
          assert.equals(ime.Apply(composer.Compose(result, ime.in_preedit)), '')
        endfor
      endfor
    endfor
    assert.equals(ime.in_preedit, true)
    assert.equals(ime.reading, 'かん')
    assert.equals(ime.okuri, 'じ')
    assert.equals(ime.okuri_started, true)
  endfor
}

suite.snapshot_retains_values_after_state_changes_and_commit = (): void => {
  const ime = state.State.new()
  assert.equals(ime.Apply(composition.Result.new(true, 'か', 'け', true)), '')
  const snapshot = ime.GetSnapshot()
  assert.equals(ime.Apply(composition.Result.new(false, 'る', '', false)), '')
  assert.equals(ime.okuri, 'ける')
  assert.equals(ime.Commit(), 'かける')
  assert.equals(snapshot.in_preedit, true)
  assert.equals(snapshot.reading, 'か')
  assert.equals(snapshot.okuri, 'け')
  assert.equals(snapshot.okuri_started, true)
}

suite.backspace_removes_empty_okuri_boundary_before_the_reading = (): void => {
  const ime = state.State.new()
  ime.Apply(composition.Result.new(true, 'かえ', 'る', true))
  assert.equals(ime.Backspace(), true)
  const after_okuri = ime.GetSnapshot()
  assert.equals(after_okuri.reading, 'かえ')
  assert.equals(after_okuri.okuri, '')
  assert.equals(after_okuri.okuri_started, true)
  assert.equals(ime.Backspace(), true)
  assert.equals(ime.reading, 'かえ')
  assert.equals(ime.okuri_started, false)
  assert.equals(ime.in_preedit, true)
  assert.equals(after_okuri.okuri_started, true)
  ime.Apply(composition.Result.new(false, 'い', '', false))
  assert.equals(ime.reading, 'かえい')
  assert.equals(ime.okuri, '')
  ime.Backspace()
  assert.equals(ime.reading, 'かえ')
}

suite.backspace_keeps_a_boundary_without_reading_until_it_is_deleted = (): void => {
  const ime = state.State.new()
  ime.Apply(composition.Result.new(true, '', 'る', true))
  assert.equals(ime.Backspace(), true)
  assert.equals(ime.in_preedit, true)
  assert.equals(ime.okuri_started, true)
  assert.equals(ime.Backspace(), true)
  assert.equals(ime.in_preedit, false)
  assert.equals(ime.okuri_started, false)
  assert.equals(ime.Backspace(), false)
}
