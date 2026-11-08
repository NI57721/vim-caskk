vim9script
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as state
final suite = themis#suite('experimental adjective')
const assert = themis#helper('assert')
suite.stem_conversion_is_marked_but_commit_is_plain = (): void => {
  const entry = parser.ParseLine('うつくし /美し;@adj/')
  const preferences = state.State.new()
  for suffix in ['い', 'か', 'く', 'け', 'き', 'し', 'う', 'そ', 'さ', 'み', 'め', 'げ', 'が', 'す']
    const prepared = conversion.Prepare({'うつくし': entry}, preferences, 'うつくし', suffix)
    assert.equals(len(prepared.candidates), 1)
    const selection = conversion.Selection.new(prepared, preferences)
    assert.equals(selection.CurrentText(), '美し' .. suffix .. '［adj］')
    assert.equals(selection.Commit(), '美し' .. suffix)
  endfor
  assert.equals(empty(preferences.GetSnapshot().mru), false)
}

suite.tags_are_per_candidate_and_duplicates_remain_separate = (): void => {
  const stem = parser.ParseLine('わる /悪;@adj/惡;「悪」の旧字(人名用漢字) @adj/誤;@adjective/違;説明/')
  const normal = parser.ParseLine('わるi /悪/')
  const preferences = state.State.new()
  const prepared = conversion.Prepare({'わる': stem, 'わるi': normal}, preferences, 'わる', 'い')
  assert.equals(mapnew(prepared.candidates, (_, candidate) => candidate.text), ['悪', '惡', '悪'])
  const selection = conversion.Selection.new(prepared, preferences)
  assert.equals(selection.GetCandidatesInfo().candidates[0].text, '悪い［adj］')
  assert.equals(selection.TogglePin(), 'pinned')
  assert.equals(selection.ToggleDemote(), 'demoted')
  assert.equals(selection.Commit(), '悪い')
  assert.equals(preferences.GetSnapshot().mru, {})
  const ordinary = conversion.Selection.new(prepared, preferences)
  ordinary.Next()
  ordinary.Next()
  assert.equals(ordinary.CurrentText(), '悪い')
  preferences.Reset(prepared.query, prepared.candidates[0].text)
  ordinary.Commit()
  assert.equals(empty(preferences.GetSnapshot().mru), false)
  assert.equals(conversion.Prepare({'わる': stem}, preferences, 'わる', 'な').candidates, [])
}

suite.user_stems_and_all_examples_are_supported = (): void => {
  const preferences = state.State.new()
  for line in ['おお /多;@adj/', 'おおき /大き;@adj/']
    const entry = parser.ParseLine(line)
    const prepared = conversion.Prepare({[entry.lookup_key]: entry}, preferences, entry.lookup_key, 'い')
    assert.equals(prepared.TextAt(0), entry.candidates[0].text .. 'い')
    preferences.AddEntry(lookup.CreateQuery(entry.lookup_key, ''), entry.candidates[0])
    const registered = conversion.Prepare({}, preferences, entry.lookup_key, 'い')
    assert.equals(registered.TextAt(0), entry.candidates[0].text .. 'い')
  endfor
}
