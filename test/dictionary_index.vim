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
