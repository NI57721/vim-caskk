vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger

final suite = themis#suite('system dictionary merge')
const assert = themis#helper('assert')

def CandidateTexts(entry: dictionary.Entry): list<string>
  final texts: list<string> = []
  for candidate in entry.candidates
    texts->add(candidate.text)
  endfor
  return texts
enddef

suite.duplicates_within_and_between_sources_keep_the_first_position = (): void => {
  const first = parser.ParseLine('かんじ /漢字/感じ/漢字/')
  const second = parser.ParseLine('かんじ /感じ/幹事/漢字/')
  const merged = merger.Merge([[first], [second]])
  assert.equals(merged['かんじ'].lookup_key, 'かんじ')
  assert.equals(CandidateTexts(merged['かんじ']), ['漢字', '感じ', '幹事'])
}

suite.source_order_determines_initial_candidate_rank = (): void => {
  const first = [parser.ParseLine('よみ /甲/乙/')]
  const second = [parser.ParseLine('よみ /乙/丙/')]
  const forward = merger.Merge([first, second])
  const reverse = merger.Merge([second, first])
  assert.equals(CandidateTexts(forward['よみ']), ['甲', '乙', '丙'])
  assert.equals(CandidateTexts(reverse['よみ']), ['乙', '丙', '甲'])
}

suite.annotations_merge_in_source_order_without_duplicates = (): void => {
  const first = parser.ParseLine('かんじ /漢字;文字/感じ;感覚/')
  const second = parser.ParseLine('かんじ /漢字;表記/漢字;文字/感じ;感覚/')
  const merged = merger.Merge([[first], [second]])
  assert.equals(CandidateTexts(merged['かんじ']), ['漢字', '感じ'])
  assert.equals(merged['かんじ'].candidates[0].annotations, ['文字', '表記'])
  assert.equals(merged['かんじ'].candidates[1].annotations, ['感覚'])
}

suite.annotations_from_repeated_candidates_in_one_entry_are_merged = (): void => {
  const entry = parser.ParseLine('よみ /字;甲/字;乙/字;甲/')
  const merged = merger.Merge([[entry]])
  assert.equals(CandidateTexts(merged['よみ']), ['字'])
  assert.equals(merged['よみ'].candidates[0].annotations, ['甲', '乙'])
}

suite.unannotated_occurrences_do_not_erase_annotations = (): void => {
  const plain = [parser.ParseLine('よみ /字/')]
  const annotated = [parser.ParseLine('よみ /字;説明/')]
  for sources in [[plain, annotated], [annotated, plain]]
    const merged = merger.Merge(sources)
    assert.equals(CandidateTexts(merged['よみ']), ['字'])
    assert.equals(merged['よみ'].candidates[0].annotations, ['説明'])
  endfor
  const unannotated = merger.Merge([plain, plain])
  assert.equals(CandidateTexts(unannotated['よみ']), ['字'])
  assert.equals(unannotated['よみ'].candidates[0].annotations, [])
}

suite.lookup_keys_are_distinct_and_candidate_identity_is_per_key = (): void => {
  const merged = merger.Merge([
    [parser.ParseLine('い /意/'), parser.ParseLine('いk /行;移動/')],
    [parser.ParseLine('いg /逝/'), parser.ParseLine('こう /行;行列/')],
  ])
  assert.equals(len(merged), 4)
  assert.equals(CandidateTexts(merged['い']), ['意'])
  assert.equals(CandidateTexts(merged['いk']), ['行'])
  assert.equals(CandidateTexts(merged['いg']), ['逝'])
  assert.equals(CandidateTexts(merged['こう']), ['行'])
  assert.equals(merged['いk'].candidates[0].annotations, ['移動'])
  assert.equals(merged['こう'].candidates[0].annotations, ['行列'])
}

suite.source_entries_are_unchanged_and_result_does_not_retain_source_lists = (): void => {
  const original = parser.ParseLine('よみ /字;甲/字;乙/')
  final first = [original]
  final second = [parser.ParseLine('よみ /字;丙/')]
  const merged = merger.Merge([first, second])
  assert.equals(len(original.candidates), 2)
  assert.equals(original.candidates[0].annotations, ['甲'])
  assert.equals(original.candidates[1].annotations, ['乙'])
  assert.equals(second[0].candidates[0].annotations, ['丙'])
  first[0] = parser.ParseLine('べつ /別/')
  second->add(parser.ParseLine('ついか /追加/'))
  assert.equals(len(merged), 1)
  assert.equals(CandidateTexts(merged['よみ']), ['字'])
  assert.equals(merged['よみ'].candidates[0].annotations, ['甲', '乙', '丙'])
}

suite.empty_sources_are_accepted_and_do_not_stop_later_sources = (): void => {
  assert.equals(merger.Merge([]), {})
  assert.equals(merger.Merge([[], []]), {})
  const merged = merger.Merge([
    [], [parser.ParseLine('よみ /甲/')], [], [parser.ParseLine('よみ /乙/')], [],
  ])
  assert.equals(CandidateTexts(merged['よみ']), ['甲', '乙'])
}

suite.candidate_and_annotation_identity_uses_exact_text = (): void => {
  const first = parser.ParseLine("key /A;Note/a/ leading /leading/か\u3099/が/")
  const second = parser.ParseLine("key /A;note/か\u3099/")
  const merged = merger.Merge([[first], [second]])
  assert.equals(CandidateTexts(merged['key']), ['A', 'a', ' leading ', 'leading', "か\u3099", 'が'])
  assert.equals(merged['key'].candidates[0].annotations, ['Note', 'note'])
}
