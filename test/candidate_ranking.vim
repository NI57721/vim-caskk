vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/candidate/ranking.vim' as ranking

final suite = themis#suite('candidate ranking')
const assert = themis#helper('assert')

def Candidates(): list<dictionary.Candidate>
  return [
    dictionary.Candidate.new('漢字', ['文字']),
    dictionary.Candidate.new('感じ', []),
    dictionary.Candidate.new('幹事', []),
    dictionary.Candidate.new('監事', []),
  ]
enddef

def Texts(candidates: list<dictionary.Candidate>): list<string>
  final texts: list<string> = []
  for candidate in candidates
    texts->add(candidate.text)
  endfor
  return texts
enddef

suite.no_preferences_preserve_source_order = (): void => {
  assert.equals(Texts(ranking.Rank(Candidates())), ['漢字', '感じ', '幹事', '監事'])
  assert.equals(ranking.Rank([]), [])
}

suite.mru_orders_normal_candidates_before_unlearned_candidates = (): void => {
  assert.equals(Texts(ranking.Rank(Candidates(), '', ['幹事', '感じ'])),
    ['幹事', '感じ', '漢字', '監事'])
}

suite.pinned_and_demoted_tiers_override_mru = (): void => {
  assert.equals(Texts(ranking.Rank(Candidates(), '感じ', ['監事', '幹事', '漢字', '感じ'], ['監事'])),
    ['感じ', '幹事', '漢字', '監事'])
}

suite.demoted_candidates_keep_source_order_even_when_used_recently = (): void => {
  assert.equals(Texts(ranking.Rank(Candidates(), '', ['監事', '感じ'], ['監事', '感じ'])),
    ['漢字', '幹事', '感じ', '監事'])
}

suite.stale_and_repeated_history_does_not_add_or_duplicate_candidates = (): void => {
  assert.equals(Texts(ranking.Rank(Candidates(), '未登録', ['未登録', '幹事', '幹事'], ['不在'])),
    ['幹事', '漢字', '感じ', '監事'])
}

suite.ranking_preserves_annotations_and_does_not_mutate_inputs = (): void => {
  final candidates = Candidates()
  final mru = ['幹事', '漢字']
  final demoted = ['監事']
  var ranked = ranking.Rank(candidates, '感じ', mru, demoted)
  assert.equals(ranked[2].annotations, ['文字'])
  remove(ranked, 0)
  assert.equals(Texts(candidates), ['漢字', '感じ', '幹事', '監事'])
  assert.equals(candidates[0].annotations, ['文字'])
  assert.equals(mru, ['幹事', '漢字'])
  assert.equals(demoted, ['監事'])
}
