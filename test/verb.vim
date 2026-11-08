vim9script
import autoload 'caskk/dictionary/loader.vim' as loader
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/user_state.vim' as state
final suite = themis#suite('experimental verbs')
const assert = themis#helper('assert')
suite.ichidan_stem_is_not_rewritten = (): void => {
  const entry = parser.ParseLine('たべ /食べ;@verb-1-shimo-b/')
  const preferences = state.State.new()
  for suffix in ['る', 'れ', 'ろ', 'よ', 'な', 'ま', 'た', 'て', 'ら', 'さ']
    const prepared = conversion.Prepare({'たべ': entry}, preferences, 'たべ', suffix)
    assert.equals(len(prepared.candidates), 1)
    const selection = conversion.Selection.new(prepared, preferences)
    assert.equals(selection.CurrentText(), '食べ' .. suffix .. '［verb］')
    assert.equals(selection.Commit(), '食べ' .. suffix)
  endfor
  assert.equals(preferences.GetSnapshot().mru, {})
}

suite.types_filter_candidates_and_preserve_ordinary_duplicates = (): void => {
  const stem = parser.ParseLine('か /書;説明 @verb-5-k @verb-classical-4-k/架;@verb-unknown/描;@verb-5-k-extra/')
  const normal = parser.ParseLine('かk /書/')
  const preferences = state.State.new()
  const prepared = conversion.Prepare({'か': stem, 'かk': normal}, preferences, 'か', 'く')
  assert.equals(mapnew(prepared.candidates, (_, item) => item.text), ['書', '書'])
  assert.equals(prepared.experimental_count, 1)
  assert.equals(conversion.Prepare({'か': stem}, preferences, 'か', 'な').candidates, [])
  const selected = conversion.Selection.new(prepared, preferences)
  selected.TogglePin()
  selected.ToggleDemote()
  selected.Commit()
  assert.equals(preferences.GetSnapshot().mru, {})
  const ordinary = conversion.Selection.new(prepared, preferences)
  ordinary.Next()
  assert.equals(ordinary.CurrentText(), '書く')
  ordinary.Commit()
  assert.equals(empty(preferences.GetSnapshot().mru), false)
}

suite.godan_sound_changes_and_irregular_types_are_distinct = (): void => {
  for [tag, allowed, rejected] in [
    ['5-k', 'い', 'っ'], ['5-k-iku', 'っ', 'い'], ['5-k-yuku', 'っ', 'い'],
    ['5-g', 'い', 'っ'], ['5-m', 'ん', 'っ'], ['5-r-aru', 'い', 'ん'],
    ['5-wa', 'っ', 'ん'], ['5-wa-iu', 'う', 'っ'], ['5-wa-yuu', 'う', 'っ'],
    ['1-shimo-r-kureru', 'れ', 'ろ'], ['1-shimo-r', 'ろ', 'ぱ'],
    ['irregular-k', 'こ', 'せ'], ['irregular-k', 'る', 'ぱ'], ['irregular-k', 'た', 'ぱ'], ['irregular-s', 'せ', 'こ'], ['irregular-z', 'じ', 'し'],
    ['classical-2-kami-k', 'き', 'け'], ['classical-2-shimo-k', 'け', 'き'],
    ['classical-irregular-n', 'ぬ', 'る'], ['classical-irregular-r', 'り', 'ぬ']]
    const entry = parser.ParseLine('よ /語;@verb-' .. tag .. '/')
    const entries = {'よ': entry}
    assert.equals(len(conversion.Prepare(entries, state.State.new(), 'よ', allowed).candidates), 1, tag)
    assert.equals(conversion.Prepare(entries, state.State.new(), 'よ', rejected).candidates, [], tag)
  endfor
}

suite.adjective_and_verb_markers_merge_without_changing_stems = (): void => {
  const entry = parser.ParseLine('よ /良;@adj @verb-5-m/')
  const prepared = conversion.Prepare({'よ': entry}, state.State.new(), 'よ', 'み')
  assert.equals(len(prepared.candidates), 1)
  const selected = conversion.Selection.new(prepared, state.State.new())
  assert.equals(selected.CurrentText(), '良み［adj,verb］')
  assert.equals(selected.Commit(), '良み')
}

suite.indexed_euc_jp_and_user_stems_keep_annotations = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(mapnew([';; okuri-ari entries.', ';; okuri-nasi entries.',
    'き /切;@verb-5-r/着;@verb-1-kami-k/',
    'たべ /食べ;説明 @verb-1-shimo-b/'],
    (_, line) => iconv(line, 'utf-8', 'euc-jp')), path)
  const database = loader.Open([loader.Source.new(path, 'euc-jp')])
  const preferences = state.State.new()
  const prepared = conversion.Prepare({}, preferences, 'たべ', 'る', true, database)
  assert.equals(prepared.TextAt(0), '食べる')
  assert.equals(prepared.candidates[0].annotations, ['説明 @verb-1-shimo-b'])
  const homonyms = conversion.Prepare({}, preferences, 'き', 'ら', true, database)
  assert.equals(mapnew(homonyms.candidates, (_, item) => item.text), ['切', '着'])
  preferences.AddEntry(lookup.CreateQuery('たべ', ''), parser.ParseLine('たべ /喰べ;@verb-1-shimo-b/').candidates[0])
  const registered = conversion.Prepare({}, preferences, 'たべ', 'な')
  assert.equals(registered.TextAt(0), '喰べな')
}

suite.all_78_types_accept_their_terminal_connection_and_reject_unrelated_kana = (): void => {
  const cases = [
    ['5-k', 'く'],
    ['5-k-iku', 'く'],
    ['5-k-yuku', 'く'],
    ['5-g', 'ぐ'],
    ['5-s', 'す'],
    ['5-t', 'つ'],
    ['5-n', 'ぬ'],
    ['5-b', 'ぶ'],
    ['5-m', 'む'],
    ['5-r', 'る'],
    ['5-r-aru', 'る'],
    ['5-wa', 'う'],
    ['5-wa-iu', 'う'],
    ['5-wa-yuu', 'う'],
    ['1-kami-a', 'る'],
    ['1-kami-k', 'る'],
    ['1-kami-g', 'る'],
    ['1-kami-z', 'る'],
    ['1-kami-t', 'る'],
    ['1-kami-n', 'る'],
    ['1-kami-h', 'る'],
    ['1-kami-b', 'る'],
    ['1-kami-m', 'る'],
    ['1-kami-r', 'る'],
    ['1-shimo-a', 'る'],
    ['1-shimo-k', 'る'],
    ['1-shimo-g', 'る'],
    ['1-shimo-s', 'る'],
    ['1-shimo-z', 'る'],
    ['1-shimo-t', 'る'],
    ['1-shimo-d', 'る'],
    ['1-shimo-n', 'る'],
    ['1-shimo-h', 'る'],
    ['1-shimo-b', 'る'],
    ['1-shimo-m', 'る'],
    ['1-shimo-r', 'る'],
    ['1-shimo-r-kureru', 'る'],
    ['irregular-k', 'く'],
    ['irregular-s', 'す'],
    ['irregular-z', 'ず'],
    ['classical-4-k', 'く'],
    ['classical-4-g', 'ぐ'],
    ['classical-4-s', 'す'],
    ['classical-4-t', 'つ'],
    ['classical-4-h-u', 'う'],
    ['classical-4-h-hu', 'ふ'],
    ['classical-4-b', 'ぶ'],
    ['classical-4-m', 'む'],
    ['classical-4-r', 'る'],
    ['classical-2-kami-k', 'く'],
    ['classical-2-kami-g', 'ぐ'],
    ['classical-2-kami-t', 'つ'],
    ['classical-2-kami-d', 'づ'],
    ['classical-2-kami-h', 'ふ'],
    ['classical-2-kami-b', 'ぶ'],
    ['classical-2-kami-m', 'む'],
    ['classical-2-kami-y', 'ゆ'],
    ['classical-2-kami-r', 'る'],
    ['classical-2-shimo-a', 'う'],
    ['classical-2-shimo-k', 'く'],
    ['classical-2-shimo-g', 'ぐ'],
    ['classical-2-shimo-s', 'す'],
    ['classical-2-shimo-z', 'ず'],
    ['classical-2-shimo-t', 'つ'],
    ['classical-2-shimo-d-zu', 'ず'],
    ['classical-2-shimo-d-du', 'づ'],
    ['classical-2-shimo-n', 'ぬ'],
    ['classical-2-shimo-h', 'ふ'],
    ['classical-2-shimo-b', 'ぶ'],
    ['classical-2-shimo-m', 'む'],
    ['classical-2-shimo-y', 'ゆ'],
    ['classical-2-shimo-r', 'る'],
    ['classical-2-shimo-w', 'う'],
    ['classical-irregular-k', 'く'],
    ['classical-irregular-s', 'す'],
    ['classical-irregular-z', 'ず'],
    ['classical-irregular-n', 'ぬ'],
    ['classical-irregular-r', 'り'],
  ]
  assert.equals(len(cases), 78)
  for [tag, ending] in cases
    const entry = parser.ParseLine('よ /語;@verb-' .. tag .. '/')
    const preferences = state.State.new()
    const entries = {'よ': entry}
    const prepared = conversion.Prepare(entries, preferences, 'よ', ending)
    assert.equals(len(prepared.candidates), 1, tag)
    assert.equals(prepared.TextAt(0), '語' .. ending, tag)
    assert.equals(conversion.Prepare(entries, preferences, 'よ', 'ぱ').candidates, [], tag)
  endfor
}

suite.bare_stems_are_hidden_but_independent_plain_sources_survive = (): void => {
  const tagged = parser.ParseLine('たべ /食べ;@verb-1-shimo-b/')
  const preferences = state.State.new()
  assert.equals(conversion.Prepare({'たべ': tagged}, preferences, 'たべ').candidates, [])
  const plain = parser.ParseLine('たべ /食べ;通常/')
  for sources in [[[tagged], [plain]], [[plain], [tagged]]]
    const combined = merger.Merge(sources)
    assert.equals(len(conversion.Prepare(combined, preferences, 'たべ').candidates), 1)
  endfor
}

suite.plain_user_and_indexed_sources_survive_snapshot_copying = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(mapnew([';; okuri-ari entries.', ';; okuri-nasi entries.',
    'たべ /食べ;@verb-1-shimo-b/'], (_, line) => iconv(line, 'utf-8', 'euc-jp')), path)
  const database = loader.Open([loader.Source.new(path, 'euc-jp')])
  const preferences = state.State.new()
  assert.equals(conversion.Prepare({}, preferences, 'たべ', '', true, database).candidates, [])
  preferences.AddEntry(lookup.CreateQuery('たべ', ''), parser.ParseLine('たべ /食べ/').candidates[0])
  const copied = state.State.new()
  copied.Restore(preferences.GetSnapshot())
  assert.equals(len(conversion.Prepare({}, copied, 'たべ', '', true, database).candidates), 1)
  const unknown = parser.ParseLine('たべ /食べ;@verb-unknown/')
  assert.equals(len(conversion.Prepare({'たべ': unknown}, state.State.new(), 'たべ').candidates), 1)
  const both = parser.ParseLine('たべ /食べ;@adj @verb-1-shimo-b/')
  assert.equals(conversion.Prepare({'たべ': both}, state.State.new(), 'たべ').candidates, [])
}
