vim9script
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/user_state.vim' as state
import autoload 'caskk/dictionary/lookup.vim' as lookup
const suite = themis#suite('stem dictionary source order')
const assert = themis#helper('assert')
suite.tags_do_not_override_dictionary_order = (): void => {
  const ordinary = dict_index.SourceFromLines(['かk /通常/', 'か /活用/'])
  const tagged = dict_index.SourceFromLines(['か /活用;@verb-5-k/'])
  for sources in [[ordinary, tagged], [tagged, ordinary]]
    const database = dict_index.Database.new(sources)
    const prepared = conversion.Prepare({}, state.State.new(), 'か', 'く', true, database)
    assert.equals(mapnew(prepared.candidates, (_, candidate) => candidate.text),
      sources[0] is ordinary ? ['通常', '活用'] : ['活用', '通常'])
  endfor
}
suite.tiers_and_learning_apply_across_candidate_kinds = (): void => {
  const database = dict_index.Database.new([dict_index.SourceFromLines(['かk /通常/']),
    dict_index.SourceFromLines(['か /活用;@verb-5-k/'])])
  const preferences = state.State.new()
  preferences.Pin(lookup.CreateQuery('か', 'く'), '通常')
  var prepared = conversion.Prepare({}, preferences, 'か', 'く', true, database)
  assert.equals(prepared.DisplayAt(0), '通常く')
  preferences.Reset(lookup.CreateQuery('か', 'く'), '通常')
  preferences.Demote(lookup.CreateQuery('か', ''), '活用')
  prepared = conversion.Prepare({}, preferences, 'か', 'く', true, database)
  assert.equals(prepared.DisplayAt(1), '活用く［verb］')
  assert.equals(conversion.Selection.new(prepared, preferences).IsExperimental(), false)
  preferences.Reset(lookup.CreateQuery('か', ''), '活用')
  preferences.Learn(lookup.CreateQuery('か', ''), '活用')
  prepared = conversion.Prepare({}, preferences, 'か', 'く', true, database)
  assert.equals(prepared.DisplayAt(0), '活用く［verb］')
}

suite.annotated_candidates_keep_their_order_within_a_dictionary = (): void => {
  const database = dict_index.Database.new([dict_index.SourceFromLines(['かな /叶;@verb-5-w/仮名;@adj/'])])
  const prepared = conversion.Prepare({}, state.State.new(), 'かな', 'い', true, database)
  assert.equals(mapnew(prepared.candidates, (_, candidate) => candidate.text), ['叶', '仮名'])
}

import autoload 'caskk/user_state/codec.vim' as codec
suite.latest_selection_wins_across_separate_histories_after_reload = (): void => {
  const database = dict_index.Database.new([dict_index.SourceFromLines(['ぎt /切/', 'ぎk /別/'])])
  const preferences = state.State.new()
  preferences.AddEntry(lookup.CreateQuery('ぎ', ''), dict_index.SourceFromLines(['ぎ /登録;@verb-5-k-iku/']).Lookup('ぎ', false)[0].candidates[0])
  preferences.Learn(lookup.CreateQuery('ぎ', 'っ'), '切')
  for attempt in range(3)
    const prepared = conversion.Prepare({}, preferences, 'ぎ', 'っ', true, database)
    const selected = conversion.Selection.new(prepared, preferences)
    selected.Select(index(mapnew(prepared.candidates, (_, candidate) => candidate.text), '登録'))
    selected.Commit()
    assert.equals(conversion.Prepare({}, preferences, 'ぎ', 'っ', true, database).TextAt(0), '登録っ')
  endfor
  const restored = state.State.new()
  restored.Restore(codec.Decode(codec.Encode(preferences.GetSnapshot())))
  assert.equals(conversion.Prepare({}, restored, 'ぎ', 'っ', true, database).TextAt(0), '登録っ')
  restored.Learn(lookup.CreateQuery('ぎ', 'く'), '別')
  assert.equals(conversion.Prepare({}, restored, 'ぎ', 'っ', true, database).TextAt(0), '登録っ')
  restored.Learn(lookup.CreateQuery('ぎ', 'っ'), '切')
  assert.equals(conversion.Prepare({}, restored, 'ぎ', 'っ', true, database).TextAt(0), '切っ')
  assert.equals(conversion.Prepare({}, restored, 'ぎ', 'か', true, database).TextAt(0), '登録か')
  restored.Pin(lookup.CreateQuery('ぎ', ''), '登録')
  assert.equals(conversion.Prepare({}, restored, 'ぎ', 'っ', true, database).TextAt(0), '登録っ')
  restored.Demote(lookup.CreateQuery('ぎ', ''), '登録')
  assert.equals(conversion.Prepare({}, restored, 'ぎ', 'っ', true, database).TextAt(0), '切っ')
}

suite.legacy_ties_keep_source_order_until_a_new_selection = (): void => {
  const database = dict_index.Database.new([dict_index.SourceFromLines([
    'ぎt /切/', 'ぎ /登録;@verb-5-k-iku/'])])
  const preferences = state.State.new()
  preferences.Restore(codec.Decode(['["caskk-user-state","1"]',
    '["mru","ぎ","っ","切"]', '["mru","ぎ","","登録"]']))
  const prepared = conversion.Prepare({}, preferences, 'ぎ', 'っ', true, database)
  assert.equals(prepared.TextAt(0), '切っ')
  const selected = conversion.Selection.new(prepared, preferences)
  selected.Select(1)
  selected.Commit()
  assert.equals(conversion.Prepare({}, preferences, 'ぎ', 'っ', true, database).TextAt(0), '登録っ')
}
