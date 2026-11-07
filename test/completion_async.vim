vim9script

import autoload 'caskk/completion.vim' as completion
import autoload 'caskk/dictionary/index.vim' as dictionary_index
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import 'caskk/dictionary.vim' as dictionary

const suite = themis#suite('incremental completion')
const assert = themis#helper('assert')

suite.prefix_search_yields_across_gaps_and_preserves_source_order = (): void => {
  const lines = [';; okuri-ari entries.', 'かなs /奏/', ';; gap', 'かなs /叶/',
    'かk /書/', ';; okuri-nasi entries.', 'か /蚊/']
    + repeat([';; ignored'], 200) + ['かな /仮名;文字/', 'かなもの /金物/', 'き /木/']
  for source in [dictionary_index.SourceFromLines(lines),
      dictionary_index.SourceFromLines(['かな /仮名/', 'かな /カナ/', 'か /蚊/'])]
    const search = source.BeginPrefix('かな')
    final found: list<dictionary.Entry> = []
    var steps = 0
    while !search.IsDone()
      const batch = search.Step(1)
      assert.equals(len(batch) <= 1, true)
      found->extend(batch)
      steps += 1
    endwhile
    assert.equals(steps > 1, true)
    const expected = merger.Merge([source.Prefix('かな')])
    const actual = merger.Merge([found])
    assert.equals(sort(keys(actual)), sort(keys(expected)))
    assert.equals(sort(keys(actual)), len(found) > 1 ? ['かな', 'かなs', 'かなもの'] : ['かな'])
    if has_key(actual, 'かなs')
      assert.equals(mapnew(actual['かなs'].candidates, (_, c) => c.text), ['奏', '叶'])
      assert.equals(actual['かな'].candidates[0].annotations, ['文字'])
    else
      assert.equals(mapnew(actual['かな'].candidates, (_, c) => c.text), ['仮名', 'カナ'])
    endif
    for key in keys(expected)
      assert.equals(mapnew(actual[key].candidates, (_, c) => c.text),
        mapnew(expected[key].candidates, (_, c) => c.text))
    endfor
  endfor
}

suite.incremental_search_preserves_annotations_okuri_and_user_preferences = (): void => {
  const database = dictionary_index.Database.new([
    dictionary_index.SourceFromLines([';; okuri-ari entries.', 'かなs /奏/',
      ';; okuri-nasi entries.', 'かな /仮名;文字/', 'かなもの /金物/']),
    dictionary_index.SourceFromLines(['かな /仮名;別注/カナ/']),
  ])
  const preferences = user_state.State.new()
  preferences.AddEntry(lookup.CreateQuery('かな', 'し'), dictionary.Candidate.new('奏', ['登録']))
  preferences.AddEntry(lookup.CreateQuery('かなもの', ''), dictionary.Candidate.new('かな物', []))
  preferences.Pin(lookup.CreateQuery('かなもの', ''), 'かな物')
  for okuri in ['', 'して']
    const search = completion.Search.new({}, preferences, 'かな', okuri, database)
    assert.equals(search.IsDone(), false)
    while !search.Step(1)
    endwhile
    const expected = completion.Prepare({}, preferences, 'かな', okuri, database)
    const found = search.Result()
    assert.equals(mapnew(found, (_, c) => [c.text, c.tier, c.okuri, string(c.learnable)]),
      mapnew(expected, (_, c) => [c.text, c.tier, c.okuri, string(c.learnable)]))
    assert.equals(mapnew(found, (_, c) => c.candidate.annotations),
      mapnew(expected, (_, c) => c.candidate.annotations))
    assert.equals(mapnew(found, (_, c) => c.text),
      okuri == '' ? ['仮名', 'カナ', '奏し', 'かな物', '金物'] : ['奏して'])
  endfor
}

suite.large_search_and_presentation_are_bounded_without_losing_candidates = (): void => {
  final entries: dict<dictionary.Entry> = {}
  for number in range(500)
    const reading = printf('おお%04d', number)
    entries[reading] = dictionary.Entry.new(reading, [dictionary.Candidate.new('候補' .. number, [])])
  endfor
  const search = completion.Search.new(entries, user_state.State.new(), 'おお')
  assert.equals(search.Step(1), false)
  while !search.Step(16)
  endwhile
  assert.equals(len(search.Result()), 500)
  const ime = session.Session.new(scheme.Compile({}, {}), '', entries, user_state.State.new(), 'おお')
  ime.ShowCompletion(2)
  ime.MoveCompletion(325)
  const info = ime.GetCompletionInfo()
  assert.equals(info.selected_index, 325)
  assert.equals(len(info.candidates) <= 20, true)
  assert.equals(index(mapnew(info.candidates, (_, c) => c.index), 325) >= 0, true)
  assert.equals(info.candidates[0].count, 500)
  assert.equals(ime.Commit()[-1].text, '候補325')
}

suite.user_state_changes_invalidate_a_pending_search = (): void => {
  const preferences = user_state.State.new()
  const search = completion.Search.new({}, preferences, 'かな')
  assert.equals(search.IsCurrent(), true)
  preferences.AddEntry(lookup.CreateQuery('かな', ''), dictionary.Candidate.new('仮名', []))
  assert.equals(search.IsCurrent(), false)
}

suite.old_results_cannot_reopen_after_input_cancellation_or_commit = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かな /仮名/')]])
  for action in ['input', 'cancel', 'commit', 'new-request']
    const ime = session.Session.new(scheme.Compile({}, {a: 'a'}), '', entries, user_state.State.new(), 'かな')
    const search = ime.CreateCompletionSearch(2)
    while !search.Step(8)
    endwhile
    if action ==# 'input'
      ime.Feed('a')
    elseif action ==# 'cancel'
      ime.CancelCompletion()
    elseif action ==# 'commit'
      ime.Commit()
    else
      ime.CreateCompletionSearch(2)
    endif
    assert.equals(ime.ApplyCompletion(search), false, action)
    assert.equals(ime.InCompletion(), false)
  endfor
}
