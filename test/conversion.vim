vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('conversion candidates')
const assert = themis#helper('assert')

suite.preparation_preserves_dictionary_order_and_annotations_without_okuri = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かんじ /漢字;文字/感じ/')]])
  const prepared = conversion.Prepare(entries, user_state.State.new(), 'かんじ')
  assert.equals(prepared.query.reading, 'かんじ')
  assert.equals(prepared.query.exact_okuri, '')
  assert.equals(prepared.query.lookup_key, 'かんじ')
  assert.equals(prepared.okuri, '')
  assert.equals(len(prepared.candidates), 2)
  assert.equals(prepared.TextAt(0), '漢字')
  assert.equals(prepared.TextAt(1), '感じ')
  assert.equals(prepared.candidates[0].annotations, ['文字'])
}

suite.full_okuri_is_appended_to_each_display_text_without_filtering = (): void => {
  const entries = merger.Merge([[parser.ParseLine('おおk /大/多/')]])
  const prepared = conversion.Prepare(entries, user_state.State.new(), 'おお', 'きい')
  assert.equals(prepared.query.reading, 'おお')
  assert.equals(prepared.query.exact_okuri, 'き')
  assert.equals(prepared.query.lookup_key, 'おおk')
  assert.equals(prepared.okuri, 'きい')
  assert.equals(prepared.TextAt(0), '大きい')
  assert.equals(prepared.TextAt(1), '多きい')
  assert.equals(prepared.candidates[0].text, '大')
  assert.equals(prepared.candidates[1].text, '多')
}

suite.user_entries_and_preferences_are_applied_before_presentation = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行;移動/往/')]])
  const preferences = user_state.State.new()
  const query = lookup.CreateQuery('い', 'くらい')
  preferences.AddEntry(query, dictionary.Candidate.new('逝', ['登録']))
  preferences.Pin(query, '逝')
  preferences.Demote(query, '行')
  const prepared = conversion.Prepare(entries, preferences, 'い', 'くれば')
  assert.equals(prepared.TextAt(0), '逝くれば')
  assert.equals(prepared.TextAt(1), '往くれば')
  assert.equals(prepared.TextAt(2), '行くれば')
  assert.equals(prepared.candidates[0].annotations, ['登録'])
  assert.equals(prepared.candidates[2].annotations, ['移動'])
}

suite.user_only_entries_are_available_when_the_system_key_is_missing = (): void => {
  const preferences = user_state.State.new()
  preferences.AddEntry(lookup.CreateQuery('あたらしい', ''), dictionary.Candidate.new('新しい', []))
  const prepared = conversion.Prepare({}, preferences, 'あたらしい')
  assert.equals(len(prepared.candidates), 1)
  assert.equals(prepared.TextAt(0), '新しい')
}

suite.preparation_does_not_learn_or_modify_sources_and_keeps_request_okuri = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/往/逝/')]])
  const preferences = user_state.State.new()
  preferences.Learn(lookup.CreateQuery('い', 'く'), '往')
  const before = codec.Encode(preferences.GetSnapshot())
  const first = conversion.Prepare(entries, preferences, 'い', 'くらい')
  const second = conversion.Prepare(entries, preferences, 'い', 'くれば')
  assert.equals(first.TextAt(0), '往くらい')
  assert.equals(second.TextAt(0), '往くれば')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  assert.equals(entries['いk'].candidates[0].text, '行')
  assert.equals(entries['いk'].candidates[1].text, '往')
  assert.equals(entries['いk'].candidates[2].text, '逝')
  const fresh = user_state.State.new()
  const fresh_before = codec.Encode(fresh.GetSnapshot())
  conversion.Prepare(entries, fresh, 'い', 'く')
  assert.equals(codec.Encode(fresh.GetSnapshot()), fresh_before)
}

suite.missing_candidates_and_out_of_range_indices_do_not_select_a_candidate = (): void => {
  const preferences = user_state.State.new()
  const missing = conversion.Prepare({}, preferences, 'みとうろく', 'く')
  assert.equals(missing.candidates, [])
  assert.equals(missing.query.reading, 'みとうろく')
  assert.equals(missing.okuri, 'く')
  const entries = merger.Merge([[parser.ParseLine('よみ /字/')]])
  const populated = conversion.Prepare(entries, preferences, 'よみ')
  for prepared in [missing, populated]
    for index in [-1, len(prepared.candidates)]
      var caught = ''
      try
        prepared.TextAt(index)
      catch
        caught = v:exception
      endtry
      assert.equals(caught, 'caskk: conversion candidate index out of range: ' .. index)
    endfor
  endfor
}
