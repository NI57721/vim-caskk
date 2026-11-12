vim9script
import autoload 'caskk/dictionary/index.vim' as index
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/user_state.vim' as state
import autoload 'caskk/dictionary/lookup.vim' as lookup
const suite = themis#suite('stem dictionary source order')
const assert = themis#helper('assert')
suite.tags_do_not_override_dictionary_order = (): void => {
  const ordinary = index.SourceFromLines(['かk /通常/', 'か /活用/'])
  const tagged = index.SourceFromLines(['か /活用;@verb-5-k/'])
  for sources in [[ordinary, tagged], [tagged, ordinary]]
    const database = index.Database.new(sources)
    const prepared = conversion.Prepare({}, state.State.new(), 'か', 'く', true, database)
    assert.equals(mapnew(prepared.candidates, (_, candidate) => candidate.text),
      sources[0] is ordinary ? ['通常', '活用'] : ['活用', '通常'])
  endfor
}
suite.tiers_and_learning_apply_across_candidate_kinds = (): void => {
  const database = index.Database.new([index.SourceFromLines(['かk /通常/']),
    index.SourceFromLines(['か /活用;@verb-5-k/'])])
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
  const database = index.Database.new([index.SourceFromLines(['かな /叶;@verb-5-w/仮名;@adj/'])])
  const prepared = conversion.Prepare({}, state.State.new(), 'かな', 'い', true, database)
  assert.equals(mapnew(prepared.candidates, (_, candidate) => candidate.text), ['叶', '仮名'])
}
