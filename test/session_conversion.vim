vim9script

import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec
import autoload 'caskk/input/mode.vim' as input_mode

final suite = themis#suite('session conversion')
const assert = themis#helper('assert')

suite.consonant_and_same_key_combination_produce_okuri_text = (): void => {
  const ime = session.Session.new(scheme.Compile({m: 'm'}, {m: 'a*ku'}))
  assert.equals(ime.Feed('m'), [])
  const results = ime.Feed('m')
  assert.equals(len(results), 1)
  assert.equals(results[0].text, 'まく')
}

suite.us_shifted_number_key_activates_okuri_boundary = (): void => {
  const compiled = scheme.Compile({k: 'k'}, {1: 'e*Tte'})
  const ordinary = session.Session.new(compiled, '', {}, null_object, '', true, 'US')
  assert.equals(ordinary.Feed('k'), [])
  const plain = ordinary.Feed('1')
  assert.equals(plain[0].state.in_preedit, false)
  assert.equals(plain[0].text, 'けって')

  const ime = session.Session.new(compiled,
    '', {}, null_object, '', true, 'US')
  assert.equals(ime.Feed('k'), [])
  const results = ime.Feed('!')
  assert.equals(len(results), 1)
  assert.equals(results[0].registration_requested, true)
  assert.equals(results[0].state.in_preedit, true)
  assert.equals(results[0].state.reading, 'け')
  assert.equals(results[0].state.okuri, 'って')
}

suite.modified_consonant_and_combination_activate_latent_okuri = (): void => {
  const ime = session.Session.new(scheme.Compile({m: 'm'}, {m: 'a*ku'}), ';')
  ime.Feed(';')
  assert.equals(ime.Feed('m'), [])
  ime.Feed(';')
  const results = ime.Feed('m')
  assert.equals(len(results), 1)
  assert.equals(results[0].registration_requested, true)
  assert.equals(results[0].state.in_preedit, true)
  assert.equals(results[0].state.reading, 'ま')
  assert.equals(results[0].state.okuri, 'く')
  assert.equals(ime.GetSnapshot().in_preedit, true)
  assert.equals(ime.GetSnapshot().reading, 'ま')
  assert.equals(ime.GetSnapshot().okuri, 'く')
}

suite.modified_mq_converts_mitsukeru_as_mitsukeru_candidate = (): void => {
  const entries = merger.Merge([[parser.ParseLine('みつk /見付/')]])
  const ime = session.Session.new(scheme.Compile({m: 'm'}, {q: 'itu*keru'}),
    '', entries, user_state.State.new())
  assert.equals(ime.Feed('M'), [])
  const results = ime.Feed('Q')
  assert.equals(len(results), 1)
  assert.equals(results[0].text, '見付ける')
  assert.equals(results[0].in_candidate, true)
  assert.equals(results[0].state.reading, 'みつ')
  assert.equals(results[0].state.okuri, 'ける')
  assert.equals(ime.GetCandidates().query.exact_okuri, 'け')
  assert.equals(ime.GetCandidates().query.lookup_key, 'みつk')
}

suite.abbreviation_mode_uses_ascii_reading_without_okuri_for_dictionary_lookup = (): void => {
  const entries = merger.Merge([[parser.ParseLine('apple /アップル/')]])
  const ime = session.Session.new(scheme.Compile({}, {}), '', entries, user_state.State.new())
  assert.equals(ime.SetInputMode(input_mode.ABBREVIATION), true)
  for key in split('apple', '\zs')
    ime.Feed(key)
  endfor
  assert.equals(ime.GetSnapshot().in_preedit, true)
  assert.equals(ime.GetSnapshot().reading, 'apple')
  assert.equals(ime.GetSnapshot().okuri, '')
  const results = ime.StartConversion(entries, user_state.State.new())
  assert.equals(results[-1].text, 'アップル')
  assert.equals(ime.GetCandidates().query.reading, 'apple')
  assert.equals(ime.GetCandidates().query.exact_okuri, '')
}

suite.abbreviation_numeric_placeholder_preserves_each_input_number = (): void => {
  const entries = merger.Merge([[parser.ParseLine('#:# /#0時#0分/')]])
  const ime = session.Session.new(scheme.Compile({}, {}), '', entries, user_state.State.new())
  ime.SetInputMode(input_mode.ABBREVIATION)
  for key in split('12:34', '\zs')
    ime.Feed(key)
  endfor
  assert.equals(ime.GetSnapshot().reading, '12:34')
  const results = ime.StartConversion(entries, user_state.State.new())
  assert.equals(results[-1].text, '12時34分')
  assert.equals(ime.GetCandidates().query.lookup_key, '#:#')
  assert.equals(ime.Commit()[-1].text, '12時34分')
}

suite.abbreviation_mode_returns_to_the_mode_it_came_from_after_candidate_commit = (): void => {
  const entries = merger.Merge([[parser.ParseLine('apple /アップル/')]])
  const ime = session.Session.new(scheme.Compile({}, {}), '', entries, user_state.State.new())
  ime.SetInputMode(input_mode.KATAKANA)
  ime.SetInputMode(input_mode.ABBREVIATION)
  for key in split('apple', '\zs')
    ime.Feed(key)
  endfor
  ime.StartConversion(entries, user_state.State.new())
  assert.equals(ime.GetInputMode(), input_mode.ABBREVIATION)
  assert.equals(ime.Commit()[-1].text, 'アップル')
  assert.equals(ime.GetInputMode(), input_mode.KATAKANA)
}

suite.input_mode_cannot_change_during_preedit_or_candidate_selection = (): void => {
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries)
  assert.equals(ime.SetInputMode(input_mode.KATAKANA), true)
  ime.Feed('K')
  assert.equals(ime.SetInputMode(input_mode.HALFWIDTH_KATAKANA), false)
  ime.Feed('a')
  ime.StartConversion(entries, user_state.State.new())
  assert.equals(ime.SetInputMode(input_mode.HALFWIDTH_KATAKANA), false)
}

suite.katakana_mode_keeps_hiragana_reading_but_displays_katakana_for_preedit_and_candidates = (): void => {
  const entries = merger.Merge([[parser.ParseLine('か /蚊か/')]])
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries)
  ime.SetInputMode(input_mode.KATAKANA)
  ime.Feed('K')
  const preedit = ime.Feed('a')[0]
  assert.equals(preedit.state.reading, 'か')
  assert.equals(preedit.preedit_text, 'カ')
  const converted = ime.StartConversion(entries, user_state.State.new())[-1]
  assert.equals(converted.text, '蚊カ')
  assert.equals(ime.Commit()[-1].text, '蚊カ')
}

suite.katakana_and_halfwidth_modes_render_okuri_candidates = (): void => {
  const entries = merger.Merge([[parser.ParseLine('ほs /欲/')]])
  const compiled = scheme.Compile({k: 'k', r: 'r', g: 'g', h: 'h', s: 's'},
    {a: 'a', e: 'e', i: 'i', o: 'o', u: 'u'})
  for [mode, expected] in [
    [input_mode.KATAKANA, 'コレガ欲シ'],
    [input_mode.HALFWIDTH_KATAKANA, 'ｺﾚｶﾞ欲ｼ'],
  ]
    const ime = session.Session.new(compiled, ';', entries)
    ime.SetInputMode(mode)
    var text = ''
    for key in split('korega;ho;si', '\zs')
      for result in ime.Feed(key)
        text ..= result.text
      endfor
    endfor
    assert.equals(text, expected)
    assert.equals(ime.GetCandidates().query.reading, 'ほ')
    assert.equals(ime.GetCandidates().query.exact_okuri, 'し')
  endfor
}

suite.fullwidth_alphanumeric_mode_outputs_direct_text_without_preedit = (): void => {
  const ime = session.Session.new(scheme.Compile({}, {}))
  ime.SetInputMode(input_mode.FULLWIDTH_ALPHANUMERIC)
  var text = ''
  for key in split('I like apples! Do you?', '\zs')
    for result in ime.Feed(key)
      text ..= result.text
      assert.equals(result.state.in_preedit, false)
    endfor
  endfor
  assert.equals(text, 'Ｉ　ｌｉｋｅ　ａｐｐｌｅｓ！　Ｄｏ　ｙｏｕ？')
}

suite.standalone_vowels_continue_kana_input_after_direct_syllables = (): void => {
  const ime = session.Session.new(scheme.Compile(
    {h: 'h', g: 'g'}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'}))
  var text = ''
  for key in split('hogeaiueo', '\zs')
    for result in ime.Feed(key)
      text ..= result.text
      assert.equals(result.state.in_preedit, false)
    endfor
  endfor
  text ..= ime.Commit()->mapnew((_, result) => result.text)->join('')
  assert.equals(text, 'ほげあいうえお')
}

suite.next_candidate_moves_in_ranked_order_without_learning = (): void => {
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/課/')]])
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  ime.StartConversion(entries, preferences)
  const before = codec.Encode(preferences.GetSnapshot())
  for text in ['科', '課']
    const result = ime.NextCandidate()
    assert.equals(result.text, text)
    assert.equals(result.in_candidate, true)
    assert.equals(result.replace_preedit, true)
    assert.equals(result.registration_requested, false)
    assert.equals(result.commit_preedit, false)
    assert.equals(result.state.reading, 'か')
  endfor
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  assert.equals(ime.Commit()[0].text, '課')
}

suite.next_after_the_last_candidate_requests_registration_without_committing = (): void => {
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  ime.StartConversion(entries, preferences)
  ime.NextCandidate()
  const before = codec.Encode(preferences.GetSnapshot())
  const request = ime.NextCandidate()
  assert.equals(request.registration_requested, true)
  assert.equals(request.in_candidate, false)
  assert.equals(request.commit_preedit, false)
  assert.equals(request.replace_preedit, true)
  assert.equals(request.text, 'か')
  assert.equals(request.state.in_preedit, true)
  assert.equals(request.state.reading, 'か')
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates().query.reading, 'か')
  assert.equals(len(ime.GetCandidates().candidates), 2)
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  var caught = ''
  try
    ime.NextCandidate()
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: no active conversion selection')
}

suite.exhausting_a_single_okuri_candidate_keeps_the_full_registration_reading = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const preferences = user_state.State.new()
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい')])
  const ime = session.Session.new(compiled, '', entries, preferences)
  ime.Feed('Z')
  assert.equals(ime.Feed('X')[0].text, '行くらい')
  const request = ime.NextCandidate()
  assert.equals(request.registration_requested, true)
  assert.equals(request.text, 'いくらい')
  assert.equals(request.commit_preedit, false)
  assert.equals(request.state.reading, 'い')
  assert.equals(request.state.okuri, 'くらい')
  assert.equals(request.state.okuri_started, true)
  assert.equals(ime.GetCandidates().query.exact_okuri, 'く')
  assert.equals(ime.GetCandidates().okuri, 'くらい')
  assert.equals(preferences.GetSnapshot().mru, {})
}

suite.cancel_restores_preedit_and_allows_reading_input_to_continue = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  const before = codec.Encode(preferences.GetSnapshot())
  const started = ime.StartConversion(entries, preferences)
  assert.equals(len(started), 1)
  assert.equals(started[0].text, '蚊')
  assert.equals(started[0].in_candidate, true)
  assert.equals(started[0].replace_preedit, true)
  assert.equals(started[0].commit_preedit, false)
  assert.equals(started[0].state.reading, 'か')
  assert.equals(ime.SelectCandidate(1).text, '科')
  const cancelled = ime.CancelConversion()
  assert.equals(cancelled.text, 'か')
  assert.equals(cancelled.in_candidate, false)
  assert.equals(cancelled.replace_preedit, true)
  assert.equals(cancelled.state.in_preedit, true)
  assert.equals(cancelled.state.reading, 'か')
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates() is null_object, true)
  ime.Feed('k')
  ime.Feed('a')
  assert.equals(ime.GetSnapshot().reading, 'かか')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.cancel_preserves_full_okuri_then_normal_input_commits_the_reading = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/往/')]])
  const preferences = user_state.State.new()
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい'),
  ])
  const ime = session.Session.new(compiled, '', entries, preferences)
  ime.Feed('Z')
  const started = ime.Feed('X')
  assert.equals(started[0].text, '行くらい')
  assert.equals(ime.GetCandidates().query.exact_okuri, 'く')
  const cancelled = ime.CancelConversion()
  assert.equals(cancelled.text, 'いくらい')
  assert.equals(cancelled.state.reading, 'い')
  assert.equals(cancelled.state.okuri, 'くらい')
  assert.equals(cancelled.state.okuri_started, true)
  const committed = ime.Feed('k')
  assert.equals(committed[0].text, 'いくらい')
  assert.equals(committed[0].commit_preedit, true)
  const direct = ime.Feed('a')
  assert.equals(direct[0].text, 'か')
  assert.equals(ime.GetSnapshot().in_preedit, false)
  assert.equals(ime.GetSnapshot().reading, '')
  assert.equals(ime.GetSnapshot().okuri, '')
  assert.equals(preferences.GetSnapshot().mru, {})
}

suite.commit_returns_selected_text_learns_and_resets_input_state = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
  ime.Feed('K')
  ime.Feed('a')
  ime.Feed(';')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  ime.StartConversion(entries, preferences)
  const changed = ime.SelectCandidate(1)
  assert.equals(changed.text, '科')
  assert.equals(changed.in_candidate, true)
  assert.equals(changed.replace_preedit, true)
  const committed = ime.Commit()
  assert.equals(len(committed), 1)
  assert.equals(committed[0].text, '科')
  assert.equals(committed[0].commit_preedit, true)
  assert.equals(committed[0].in_candidate, false)
  assert.equals(committed[0].state.in_preedit, false)
  assert.equals(committed[0].state.reading, '')
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates() is null_object, true)
  assert.equals(preferences.GetSnapshot().mru[json_encode(['か', ''])], ['科'])
  assert.equals(ime.Commit(), [])
  ime.Feed('k')
  const direct = ime.Feed('a')
  assert.equals(direct[0].text, 'か')
  assert.equals(direct[0].state.in_preedit, false)
}

suite.pending_special_is_flushed_before_dictionary_lookup = (): void => {
  const ime = session.Session.new(scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['a'], 'か'),
    scheme.SpecialDefinition.new(['a', 'b'], 'かん'),
  ]))
  ime.Feed('A')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  const results = ime.StartConversion(entries, user_state.State.new())
  assert.equals(len(results), 2)
  assert.equals(results[0].state.reading, 'か')
  assert.equals(results[0].in_candidate, false)
  assert.equals(results[1].text, '蚊')
  assert.equals(results[1].in_candidate, true)
  assert.equals(ime.Pending(), [])
}

suite.unhandled_named_pending_input_does_not_start_candidate_selection = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k', '<F11>': 'k'}, {a: 'a'}))
  for key in ['K', 'a', '<F11>']
    ime.Feed(key)
  endfor
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  const results = ime.StartConversion(entries, user_state.State.new())
  assert.equals(len(results), 1)
  assert.equals(results[0].unhandled[0].key, '<F11>')
  assert.equals(results[0].state.reading, 'か')
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates() is null_object, true)
}

suite.no_candidates_preserve_reading_and_expose_the_registration_query = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  assert.equals(ime.StartConversion({}, user_state.State.new()), [])
  ime.Feed('K')
  ime.Feed('a')
  const results = ime.StartConversion({}, user_state.State.new())
  assert.equals(results[0].state.in_preedit, true)
  assert.equals(results[0].state.reading, 'か')
  assert.equals(results[0].in_candidate, false)
  assert.equals(results[0].replace_preedit, false)
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates().query.reading, 'か')
  assert.equals(ime.GetCandidates().candidates, [])
}

suite.active_selection_rejects_restarting_conversion = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  ime.StartConversion(entries, preferences)
  var caught = ''
  try
    ime.StartConversion(entries, preferences)
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: conversion selection is active')
  assert.equals(ime.InCandidate(), true)
  assert.equals(ime.GetSnapshot().reading, 'か')
  assert.equals(ime.Pending(), [])
  assert.equals(ime.SelectCandidate(1).text, '科')
  assert.equals(ime.Commit()[0].text, '科')
}

suite.normal_input_commits_the_selected_candidate_then_keeps_the_new_pending_key = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  const preferences = user_state.State.new()
  ime.StartConversion(entries, preferences)
  ime.SelectCandidate(1)
  const results = ime.Feed('k')
  assert.equals(len(results), 1)
  assert.equals(results[0].text, '科')
  assert.equals(results[0].commit_preedit, true)
  assert.equals(results[0].state.in_preedit, false)
  assert.equals(results[0].in_candidate, false)
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.GetCandidates() is null_object, true)
  assert.equals(ime.Pending()[0].key, 'k')
  assert.equals(preferences.GetSnapshot().mru[json_encode(['か', ''])], ['科'])
  const following = ime.Feed('a')
  assert.equals(len(following), 1)
  assert.equals(following[0].text, 'か')
  assert.equals(following[0].commit_preedit, false)
  assert.equals(following[0].state.in_preedit, false)
}

suite.standalone_vowel_after_candidate_commit_stays_direct_until_modified_input = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a', i: 'i'}), ';')
  ime.Feed('K')
  ime.Feed('a')
  ime.StartConversion(merger.Merge([[parser.ParseLine('か /蚊/')]]), user_state.State.new())
  const direct = ime.Feed('i')
  assert.equals(len(direct), 2)
  assert.equals(direct[0].text, '蚊')
  assert.equals(direct[1].text, 'い')
  assert.equals(direct[1].state.in_preedit, false)

  ime.Feed(';')
  const modified = ime.Feed('i')
  assert.equals(modified[-1].text, '')
  assert.equals(modified[-1].state.in_preedit, true)
  assert.equals(modified[-1].state.reading, 'い')
}

suite.commit_result_precedes_direct_output_from_the_same_input = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}, [scheme.SpecialDefinition.new(['x'], '。')]))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  ime.StartConversion(entries, user_state.State.new())
  const results = ime.Feed('x')
  assert.equals(len(results), 2)
  assert.equals(results[0].text, '蚊')
  assert.equals(results[0].commit_preedit, true)
  assert.equals(results[1].text, '。')
  assert.equals(results[1].commit_preedit, false)
  assert.equals(results[1].state.in_preedit, false)
}

suite.modified_and_sticky_input_start_a_new_preedit_after_committing = (): void => {
  for keys in [['K', 'a'], [';', 'k', 'a']]
    const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), ';')
    ime.Feed('K')
    ime.Feed('a')
    const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
    ime.StartConversion(entries, user_state.State.new())
    const committed = ime.Feed(keys[0])
    assert.equals(len(committed), 1)
    assert.equals(committed[0].text, '蚊')
    assert.equals(committed[0].commit_preedit, true)
    for key in keys[1 :]
      ime.Feed(key)
    endfor
    assert.equals(ime.GetSnapshot().in_preedit, true)
    assert.equals(ime.GetSnapshot().reading, 'か')
    assert.equals(ime.GetSnapshot().okuri, '')
    assert.equals(committed[0].state.in_preedit, false)
    assert.equals(committed[0].state.reading, '')
  endfor
}

suite.unhandled_input_is_returned_after_the_candidate_commit = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  ime.StartConversion(entries, user_state.State.new())
  const results = ime.Feed('<F11>')
  assert.equals(len(results), 2)
  assert.equals(results[0].text, '蚊')
  assert.equals(results[0].commit_preedit, true)
  assert.equals(results[1].text, '')
  assert.equals(results[1].unhandled[0].key, '<F11>')
  assert.equals(results[1].state.in_preedit, false)
}

suite.pending_literal_input_is_included_before_dictionary_lookup = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  for key in ['K', 'a', 'k']
    ime.Feed(key)
  endfor
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  const results = ime.StartConversion(entries, user_state.State.new())
  assert.equals(len(results), 2)
  assert.equals(results[0].state.reading, 'かk')
  assert.equals(results[1].registration_requested, true)
  assert.equals(ime.GetCandidates().query.reading, 'かk')
  assert.equals(ime.InCandidate(), false)
}

suite.literal_input_is_returned_after_the_candidate_commit = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  ime.Feed('K')
  ime.Feed('a')
  const entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  ime.StartConversion(entries, user_state.State.new())
  const results = ime.Feed('?')
  assert.equals(len(results), 2)
  assert.equals(results[0].text, '蚊')
  assert.equals(results[0].commit_preedit, true)
  assert.equals(results[1].text, '?')
  assert.equals(results[1].unhandled, [])
  assert.equals(results[1].state.in_preedit, false)
}

suite.selection_actions_outside_candidate_state_are_rejected = (): void => {
  const ime = session.Session.new(scheme.Compile({}, {}))
  for action in ['select', 'cancel', 'previous', 'next']
    var caught = ''
    try
      if action ==# 'select'
        ime.SelectCandidate(0)
      elseif action ==# 'previous'
        ime.PreviousCandidate()
      elseif action ==# 'next'
        ime.NextCandidate()
      else
        ime.CancelConversion()
      endif
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: no active conversion selection')
    assert.equals(ime.GetSnapshot().in_preedit, false)
  endfor
}
