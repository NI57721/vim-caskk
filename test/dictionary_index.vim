vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/loader.vim' as loader
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/index.vim' as dict_index

final suite = themis#suite('sorted system dictionary index')
const assert = themis#helper('assert')

def CandidateTexts(candidates: list<dictionary.Candidate>): list<string>
  return mapnew(candidates, (_, candidate) => candidate.text)
enddef

suite.binary_search_uses_descending_okuri_and_ascending_plain_sections = (): void => {
  const path = tempname()
  defer delete(path)
  writefile([';; okuri-ari entries.', 'こk /濃/', 'malformed row', 'かk /書/', 'あk /明/',
    ';; okuri-nasi entries.', 'あ /亜/', 'か /蚊/', 'こ /個/'], path)
  const database = loader.Open([loader.Source.new(path)])
  assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('か', 'く'))), ['書'])
  assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('か', ''))), ['蚊'])
  assert.equals(len(database.Lookup(lookup.CreateQuery('さ', ''))), 0)
}

suite.binary_search_uses_the_source_encoding_order_for_euc_jp_sections = (): void => {
  const lines = [';; okuri-ari entries.', ';; okuri-nasi entries.',
    'しゅうせいていあん /候補/', 'なかあだち /候補/',
    'べつぶんしょ /候補/', 'ほんやくじ /候補/', 'ぼせいほご /候補/', 'ぽあそんひ /候補/',
    'ぽりぶくろ /候補/', 'ぽんとちょう /候補/', 'ぽんぷしゃ /候補/', 'ま> /候補/',
    'まーじゃん /候補/', 'まーじゃんよう /候補/', 'まいかい /毎回/',
    'まいくろめーとる /候補/', 'まいにち /候補/', 'まくらざき /候補/',
    'まんず /候補/', 'ものがたりてき /候補/']
  const database = dict_index.Database.new([dict_index.SourceFromLines(lines, 'euc-jp')])
  assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('まいかい', ''))), ['毎回'])
}

suite.binary_search_preserves_source_order_and_merges_duplicate_annotations = (): void => {
  const first = tempname()
  const second = tempname()
  defer delete(first)
  defer delete(second)
  writefile([';; okuri-nasi entries.', 'か /蚊;昆虫/科/'], first)
  writefile([';; okuri-nasi entries.', 'か /蚊;虫/課/'], second)
  const database = loader.Open([loader.Source.new(first), loader.Source.new(second)])
  const candidates = database.Lookup(lookup.CreateQuery('か', ''))
  assert.equals(CandidateTexts(candidates), ['蚊', '科', '課'])
  assert.equals(candidates[0].annotations, ['昆虫', '虫'])
}

suite.single_matching_entry_still_deduplicates_its_candidates = (): void => {
  const path = tempname()
  defer delete(path)
  writefile([';; okuri-nasi entries.', 'か /蚊/蚊;昆虫/'], path)
  const database = loader.Open([loader.Source.new(path)])
  const candidates = database.Lookup(lookup.CreateQuery('か', ''))
  assert.equals(CandidateTexts(candidates), ['蚊'])
  assert.equals(candidates[0].annotations, ['昆虫'])
}

suite.sectionless_dictionary_uses_the_existing_unsorted_lookup_behavior = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(['こ /個/', 'あ /亜/', 'か /蚊/'], path)
  const database = loader.Open([loader.Source.new(path)])
  assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('あ', ''))), ['亜'])
  assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('か', ''))), ['蚊'])
}

suite.incremental_builder_matches_the_synchronous_index_across_small_steps = (): void => {
  const lines = [';; okuri-ari entries.', 'こk /濃/', 'malformed row', 'かk /書/', 'あk /明/',
    ';; okuri-nasi entries.', 'あ /亜/', 'か /蚊/', 'こ /個/']
  const builder = dict_index.Builder.new(lines)
  assert.equals(builder.IsDone(), false)
  while !builder.IsDone()
    builder.Step(2)
  endwhile
  const database = dict_index.Database.new([builder.Result()])
  const synchronous = dict_index.Database.new([dict_index.SourceFromLines(lines)])
  assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('か', 'く'))),
    CandidateTexts(synchronous.Lookup(lookup.CreateQuery('か', 'く'))))
  assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('か', ''))), ['蚊'])
}

suite.incremental_builder_keeps_sectionless_duplicate_merge_behavior = (): void => {
  const lines = ['よみ /甲/', 'よみ /乙/', '別 /別候補/']
  const builder = dict_index.Builder.new(lines)
  while !builder.IsDone()
    builder.Step(1)
  endwhile
  const database = dict_index.Database.new([builder.Result()])
  const candidates = database.Lookup(lookup.CreateQuery('よみ', ''))
  assert.equals(CandidateTexts(candidates), ['甲', '乙'])
}

suite.duplicates_across_ignored_rows_preserve_candidates_in_both_sections = (): void => {
  const lines = [';; okuri-ari entries.', '', 'こk /濃/', 'かk /書;動詞/',
    'malformed row', '  ;; comment', '', 'かk /', 'かk /描/', 'あk /明/', '',
    ';; okuri-nasi entries.', '', 'あ /亜/', 'か /蚊;昆虫/', 'malformed row',
    '  ;; comment', '', 'か /', 'か /科/', 'こ /個/', 'malformed row']
  const builder = dict_index.Builder.new(lines)
  while !builder.Step(1)
  endwhile
  for source in [dict_index.SourceFromLines(lines), builder.Result()]
    const database = dict_index.Database.new([source])
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('か', 'く'))), ['書', '描'])
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('か', ''))), ['蚊', '科'])
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('あ', 'く'))), ['明'])
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('こ', ''))), ['個'])
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('さ', ''))), [])
  endfor
}

suite.section_boundaries_are_ready_after_one_scan = (): void => {
  const lines = [';; okuri-ari entries.', 'かk /書/', ';; okuri-nasi entries.', 'か /蚊/']
  const builder = dict_index.Builder.new(lines)
  builder.Step(len(lines))
  assert.equals(builder.Step(1), true)
}

suite.empty_or_ignored_sections_return_no_candidates = (): void => {
  for lines in [[';; okuri-ari entries.', ';; okuri-nasi entries.'],
      [';; okuri-ari entries.', '', 'bad row', ';; okuri-nasi entries.', ';; comment', '']]
    const database = dict_index.Database.new([dict_index.SourceFromLines(lines)])
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('か', 'く'))), [])
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery('か', ''))), [])
  endfor
}


suite.binary_search_skips_long_gaps_at_midpoints_and_section_edges = (): void => {
  const gap = repeat(['', ';; comment', 'invalid row'], 8)
  var okuri = copy(gap)
  var plain = copy(gap)
  for key in ['あ', 'か', 'さ', 'た', 'な']
    okuri->extend([key .. 'k /' .. key .. '/'])->extend(gap)
    plain->extend([key .. ' /' .. key .. '/'])->extend(gap)
  endfor
  const lines = [';; okuri-ari entries.'] + reverse(okuri) + [';; okuri-nasi entries.'] + plain
  const database = dict_index.Database.new([dict_index.SourceFromLines(lines)])
  for key in ['あ', 'か', 'さ', 'た', 'な']
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery(key, 'く'))), [key])
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery(key, ''))), [key])
  endfor
  for key in ['い', 'き', 'ん']
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery(key, 'く'))), [])
    assert.equals(CandidateTexts(database.Lookup(lookup.CreateQuery(key, ''))), [])
  endfor
}

suite.section_boundary_search_finishes_without_visiting_every_entry = (): void => {
  for sizes in [[8192, 7], [7, 8192], [4096, 4096]]
    const lines = repeat([';; preamble'], 8) + [';; okuri-ari entries.']
      + repeat(['かk /書/'], sizes[0]) + [';; okuri-nasi entries.']
      + repeat(['word /単語/'], sizes[1])
    const builder = dict_index.Builder.new(lines)
    assert.equals(builder.Step(64), true)
    const source = builder.Result()
    assert.equals(len(source.Lookup('word', false)), sizes[1])
    assert.equals(len(source.Lookup('かk', true)), sizes[0])
    assert.equals(source.Lookup('word', true), [])
  endfor
}

suite.section_boundary_search_handles_empty_sections_and_ignored_midpoints = (): void => {
  for sizes in [[0, 100], [100, 0], [0, 0]]
    const lines = [';; okuri-ari entries.'] + repeat(['かk /書/'], sizes[0])
      + repeat(['invalid row', ';; comment', ''], 20) + [';; okuri-nasi entries.']
      + repeat(['word /単語/'], sizes[1]) + repeat([';; trailing comment'], 20)
    const builder = dict_index.Builder.new(lines)
    var steps = 0
    while !builder.Step(1)
      steps += 1
      assert.equals(steps <= len(lines) * 3, true)
    endwhile
    const source = builder.Result()
    assert.equals(len(source.Lookup('かk', true)), sizes[0])
    assert.equals(len(source.Lookup('word', false)), sizes[1])
  endfor
}

suite.ambiguous_boundary_probe_falls_back_to_the_actual_section_headers = (): void => {
  # Non-okuri keys in the okuri section must not create an inferred boundary.
  const lines = [';; okuri-ari entries.'] + repeat(['あ /亜/'], 101)
    + [';; okuri-nasi entries.', 'word /単語/']
  const source = dict_index.SourceFromLines(lines)
  assert.equals(len(source.Lookup('あ', true)), 101)
  assert.equals(len(source.Lookup('word', false)), 1)
  assert.equals(source.Lookup('あ', false), [])
}
