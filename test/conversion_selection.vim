vim9script

import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('conversion selection')
const assert = themis#helper('assert')

suite.next_moves_in_ranked_order_without_learning_until_commit = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かんじ /漢字/感じ/幹事/')]])
  const preferences = user_state.State.new()
  preferences.Pin(lookup.CreateQuery('かんじ', ''), '感じ')
  const before = codec.Encode(preferences.GetSnapshot())
  const selected = conversion.Selection.new(conversion.Prepare(entries, preferences, 'かんじ'), preferences)
  assert.equals(selected.CurrentText(), '感じ')
  assert.equals(selected.Next(), true)
  assert.equals(selected.CurrentText(), '漢字')
  assert.equals(selected.Next(), true)
  assert.equals(selected.CurrentText(), '幹事')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  assert.equals(selected.Commit(), '幹事')
  assert.equals(preferences.GetSnapshot().mru[json_encode(['かんじ', ''])], ['幹事'])
}

suite.selection_only_learns_when_committed = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かんじ /漢字/感じ/')]])
  const preferences = user_state.State.new()
  const before = codec.Encode(preferences.GetSnapshot())
  const selected = conversion.Selection.new(conversion.Prepare(entries, preferences, 'かんじ'), preferences)
  assert.equals(selected.IsActive(), true)
  assert.equals(selected.CurrentText(), '漢字')
  assert.equals(selected.Select(1), '感じ')
  assert.equals(selected.CurrentText(), '感じ')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  assert.equals(selected.Commit(), '感じ')
  assert.equals(selected.IsActive(), false)
  assert.equals(conversion.Prepare(entries, preferences, 'かんじ').TextAt(0), '感じ')
}

suite.commit_keeps_full_okuri_but_learns_only_the_candidate_body = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/往/')]])
  const preferences = user_state.State.new()
  const selected = conversion.Selection.new(conversion.Prepare(entries, preferences, 'い', 'くらい'), preferences)
  assert.equals(selected.Select(1), '往くらい')
  assert.equals(selected.Commit(), '往くらい')
  const snapshot = preferences.GetSnapshot()
  assert.equals(snapshot.mru[json_encode(['い', 'く'])], ['往'])
  assert.equals(conversion.Prepare(entries, preferences, 'い', 'くれば').TextAt(0), '往くれば')
  assert.equals(conversion.Prepare(entries, preferences, 'い', 'こない').TextAt(0), '行こない')
}

suite.cancel_returns_the_original_reading_and_full_okuri_without_learning = (): void => {
  const entries = merger.Merge([[parser.ParseLine('いk /行/往/')]])
  const preferences = user_state.State.new()
  const before = codec.Encode(preferences.GetSnapshot())
  const selected = conversion.Selection.new(conversion.Prepare(entries, preferences, 'い', 'くらい'), preferences)
  selected.Select(1)
  assert.equals(selected.Cancel(), 'いくらい')
  assert.equals(selected.IsActive(), false)
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  const plain_entries = merger.Merge([[parser.ParseLine('かんじ /漢字/')]])
  const plain = conversion.Selection.new(conversion.Prepare(plain_entries, preferences, 'かんじ'), preferences)
  assert.equals(plain.Cancel(), 'かんじ')
}

suite.committing_pinned_or_demoted_candidates_preserves_explicit_choices = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かんじ /漢字/感じ/幹事/')]])
  const preferences = user_state.State.new()
  const query = lookup.CreateQuery('かんじ', '')
  preferences.Pin(query, '感じ')
  preferences.Demote(query, '幹事')
  const before = codec.Encode(preferences.GetSnapshot())
  const pinned = conversion.Selection.new(conversion.Prepare(entries, preferences, 'かんじ'), preferences)
  assert.equals(pinned.Commit(), '感じ')
  const demoted = conversion.Selection.new(conversion.Prepare(entries, preferences, 'かんじ'), preferences)
  assert.equals(demoted.Select(2), '幹事')
  assert.equals(demoted.Commit(), '幹事')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.invalid_index_preserves_the_selection_and_learning_state = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かんじ /漢字/感じ/')]])
  const preferences = user_state.State.new()
  const before = codec.Encode(preferences.GetSnapshot())
  const selected = conversion.Selection.new(conversion.Prepare(entries, preferences, 'かんじ'), preferences)
  selected.Select(1)
  for index in [-1, 2]
    var caught = ''
    try
      selected.Select(index)
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: conversion candidate index out of range: ' .. index)
    assert.equals(selected.CurrentText(), '感じ')
    assert.equals(selected.IsActive(), true)
    assert.equals(codec.Encode(preferences.GetSnapshot()), before)
  endfor
}

suite.completed_selection_rejects_further_actions_without_learning = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かんじ /漢字/感じ/')]])
  for finish in ['commit', 'cancel']
    const preferences = user_state.State.new()
    const selected = conversion.Selection.new(conversion.Prepare(entries, preferences, 'かんじ'), preferences)
    if finish ==# 'commit'
      selected.Commit()
    else
      selected.Cancel()
    endif
    const before = codec.Encode(preferences.GetSnapshot())
    for action in ['commit', 'cancel', 'select', 'current', 'next', 'previous']
      var caught = ''
      try
        if action ==# 'commit'
          selected.Commit()
        elseif action ==# 'cancel'
          selected.Cancel()
        elseif action ==# 'select'
          selected.Select(1)
        elseif action ==# 'next'
          selected.Next()
        elseif action ==# 'previous'
          selected.Previous()
        else
          selected.CurrentText()
        endif
      catch
        caught = v:exception
      endtry
      assert.equals(caught, 'caskk: conversion selection is already closed')
      assert.equals(codec.Encode(preferences.GetSnapshot()), before)
    endfor
  endfor
}

suite.empty_candidates_cannot_start_selection = (): void => {
  const preferences = user_state.State.new()
  const prepared = conversion.Prepare({}, preferences, 'みとうろく')
  var caught = ''
  try
    conversion.Selection.new(prepared, preferences)
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: cannot select from empty conversion candidates')
  assert.equals(prepared.query.reading, 'みとうろく')
  assert.equals(codec.Encode(preferences.GetSnapshot()), ['["caskk-user-state","1"]'])
}
