vim9script

import 'caskk/dictionary.vim' as dictionary
import 'caskk/composition.vim' as composition
import autoload 'caskk/state.vim' as state
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger

final suite = themis#suite('system dictionary lookup')
const assert = themis#helper('assert')

def CandidateTexts(candidates: list<dictionary.Candidate>): list<string>
  final texts: list<string> = []
  for candidate in candidates
    texts->add(candidate.text)
  endfor
  return texts
enddef

suite.query_without_okuri_uses_reading_unchanged = (): void => {
  const query = lookup.CreateQuery('かんじ', '')
  assert.equals(query.reading, 'かんじ')
  assert.equals(query.exact_okuri, '')
  assert.equals(query.lookup_key, 'かんじ')
}

suite.query_preserves_reading_and_exact_okuri_separately_from_lookup_key = (): void => {
  const query = lookup.CreateQuery('い', 'く')
  assert.equals(query.reading, 'い')
  assert.equals(query.exact_okuri, 'く')
  assert.equals(query.lookup_key, 'いk')
}

suite.ddskk_standard_okuri_prefixes_are_used = (): void => {
  const groups = [
    ['x', 'ぁぃぅぇぉっゃゅょゎゐゑ'],
    ['a', 'あ'], ['i', 'い'], ['u', 'う'], ['e', 'え'], ['o', 'お'],
    ['k', 'かきくけこ'], ['g', 'がぎぐげご'],
    ['s', 'さしすせそ'], ['z', 'ざずぜぞ'], ['j', 'じ'],
    ['t', 'たちつてと'], ['d', 'だぢづでど'],
    ['n', 'なにぬねのん'], ['h', 'はひふへほ'],
    ['b', 'ばびぶべぼ'], ['p', 'ぱぴぷぺぽ'], ['m', 'まみむめも'],
    ['y', 'やゆよ'], ['r', 'らりるれろ'], ['w', 'わを'],
  ]
  for group in groups
    for kana in split(group[1], '\zs')
      const query = lookup.CreateQuery('よみ', kana, false)
      assert.equals(query.reading, 'よみ')
      assert.equals(query.exact_okuri, kana)
      assert.equals(query.lookup_key, 'よみ' .. group[0])
    endfor
  endfor
}

suite.same_initial_okuri_shares_exact_identity = (): void => {
  for okuri in ['く', 'くらい', 'くれば']
    const query = lookup.CreateQuery('い', okuri)
    assert.equals(query.lookup_key, 'いk')
    assert.equals(query.exact_okuri, 'く')
    assert.equals(query.reading .. query.exact_okuri, 'いく')
  endfor
}

suite.different_initial_okuri_keeps_distinct_exact_identity_for_the_same_key = (): void => {
  const first = lookup.CreateQuery('い', 'くらい')
  const second = lookup.CreateQuery('い', 'こない')
  assert.equals(first.lookup_key, 'いk')
  assert.equals(second.lookup_key, 'いk')
  assert.equals(first.exact_okuri, 'く')
  assert.equals(second.exact_okuri, 'こ')
}

suite.full_display_okuri_is_retained_while_exact_identity_is_shortened = (): void => {
  const ime = state.State.new()
  assert.equals(ime.Apply(composition.Result.new(true, 'い', 'くらい', true)), '')
  const query = lookup.CreateQuery(ime.reading, ime.okuri)
  assert.equals(query.reading, 'い')
  assert.equals(query.exact_okuri, 'く')
  assert.equals(ime.okuri, 'くらい')
  assert.equals(ime.Commit(), 'いくらい')
}

suite.small_tsu_uses_t_prefix_by_default_and_can_use_standard_x_prefix = (): void => {
  for okuri in ['っ', 'って']
    const query = lookup.CreateQuery('か', okuri)
    assert.equals(query.reading, 'か')
    assert.equals(query.exact_okuri, 'っ')
    assert.equals(query.lookup_key, 'かっt')

    const standard = lookup.CreateQuery('か', okuri, false)
    assert.equals(standard.lookup_key, 'かx')
  endfor
}

suite.okuri_outside_the_standard_table_is_rejected = (): void => {
  for okuri in ['A', '!', 'ゔ', 'カ']
    var caught = ''
    try
      lookup.CreateQuery('い', okuri)
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: unsupported SKK okuri: ' .. okuri)
  endfor
}

suite.reading_and_okuri_keys_select_distinct_entries = (): void => {
  const entries = merger.Merge([[
    parser.ParseLine('い /意/'), parser.ParseLine('いk /行/'), parser.ParseLine('いg /逝/'),
  ]])
  assert.equals(CandidateTexts(lookup.Lookup(entries, lookup.CreateQuery('い', ''))), ['意'])
  assert.equals(CandidateTexts(lookup.Lookup(entries, lookup.CreateQuery('い', 'く'))), ['行'])
  assert.equals(CandidateTexts(lookup.Lookup(entries, lookup.CreateQuery('い', 'ぐ'))), ['逝'])
}

suite.lookup_retains_merged_candidate_order_and_annotations = (): void => {
  const entries = merger.Merge([
    [parser.ParseLine('かんじ /漢字;文字/感じ/')],
    [parser.ParseLine('かんじ /漢字;表記/幹事/')],
  ])
  const candidates = lookup.Lookup(entries, lookup.CreateQuery('かんじ', ''))
  assert.equals(CandidateTexts(candidates), ['漢字', '感じ', '幹事'])
  assert.equals(candidates[0].annotations, ['文字', '表記'])
}

suite.exact_okuri_does_not_filter_candidates_or_get_appended_to_text = (): void => {
  const entries = merger.Merge([[parser.ParseLine('おおk /大/多/')]])
  for okuri in ['き', 'く']
    const candidates = lookup.Lookup(entries, lookup.CreateQuery('おお', okuri))
    assert.equals(CandidateTexts(candidates), ['大', '多'])
  endfor
}

suite.missing_key_returns_an_empty_list = (): void => {
  const query = lookup.CreateQuery('みとうろく', '')
  assert.equals(lookup.Lookup({}, query), [])
  const entries = merger.Merge([[parser.ParseLine('ほか /他/')]])
  assert.equals(lookup.Lookup(entries, query), [])
}

suite.returned_list_can_change_without_altering_system_candidates = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かんじ /漢字/感じ/')]])
  const query = lookup.CreateQuery('かんじ', '')
  var candidates = lookup.Lookup(entries, query)
  remove(candidates, 0)
  candidates->add(dictionary.Candidate.new('変更', []))
  assert.equals(CandidateTexts(candidates), ['感じ', '変更'])
  assert.equals(CandidateTexts(lookup.Lookup(entries, query)), ['漢字', '感じ'])
  assert.equals(CandidateTexts(entries['かんじ'].candidates), ['漢字', '感じ'])
}
