vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/loader.vim' as loader
import autoload 'caskk/dictionary/lookup.vim' as lookup

final suite = themis#suite('system dictionary loader')
const assert = themis#helper('assert')

def CandidateTexts(entry: dictionary.Entry): list<string>
  final texts: list<string> = []
  for candidate in entry.candidates
    texts->add(candidate.text)
  endfor
  return texts
enddef

suite.utf8_file_preserves_keys_candidates_and_annotations = (): void => {
  const path = tempname()
  defer delete(path)
  writefile([';; okuri-ari entries.', 'いk /行/往/', ';; okuri-nasi entries.',
    'かんじ /漢字;文字/感じ/', ''], path)
  const entries = loader.Load([loader.Source.new(path)])
  assert.equals(len(entries), 2)
  assert.equals(CandidateTexts(entries['いk']), ['行', '往'])
  assert.equals(CandidateTexts(entries['かんじ']), ['漢字', '感じ'])
  assert.equals(entries['かんじ'].candidates[0].annotations, ['文字'])
}

suite.euc_jp_source_is_decoded_before_merging_with_utf8 = (): void => {
  const utf8_path = tempname()
  const euc_path = tempname()
  defer delete(utf8_path)
  defer delete(euc_path)
  writefile(['かな /仮名;表記/'], utf8_path)
  # Fixed EUC-JP bytes for 'かな /仮名;注釈/' followed by LF.
  writefile(0zA4ABA4CA202FB2BECCBE3BC3EDBCE12F0A, euc_path)
  const entries = loader.Load([loader.Source.new(utf8_path), loader.Source.new(euc_path, 'euc-jp')])
  assert.equals(len(entries), 1)
  assert.equals(CandidateTexts(entries['かな']), ['仮名'])
  assert.equals(entries['かな'].candidates[0].annotations, ['表記', '注釈'])
}

suite.euc_jp_dictionary_search_uses_the_encoded_key_sort_order = (): void => {
  const path = tempname()
  defer delete(path)
  const lines = [';; okuri-ari entries.', ';; okuri-nasi entries.',
    'しゅうせいていあん /候補/', 'なかあだち /候補/', 'べつぶんしょ /候補/',
    'ほんやくじ /候補/', 'ぼせいほご /候補/', 'ぽあそんひ /候補/', 'ぽりぶくろ /候補/',
    'ぽんとちょう /候補/', 'ぽんぷしゃ /候補/', 'ま> /候補/', 'まーじゃん /候補/',
    'まーじゃんよう /候補/', 'まいかい /毎回/', 'まいくろめーとる /候補/',
    'まいにち /候補/', 'まくらざき /候補/', 'まんず /候補/', 'ものがたりてき /候補/']
  writefile(mapnew(lines, (_, line) => iconv(line, 'utf-8', 'euc-jp')), path)
  const database = loader.Open([loader.Source.new(path, 'euc-jp')])
  const query = lookup.CreateQuery('まいかい', '')
  assert.equals(mapnew(database.Lookup(query), (_, candidate) => candidate.text), ['毎回'])
  const builder = loader.DatabaseBuilder.new([loader.Source.new(path, 'euc-jp')])
  while !builder.IsDone()
    builder.Step(3)
  endwhile
  assert.equals(mapnew(builder.Result().Lookup(query), (_, candidate) => candidate.text), ['毎回'])
}

suite.file_and_line_order_determine_candidate_order = (): void => {
  const first_path = tempname()
  const second_path = tempname()
  defer delete(first_path)
  defer delete(second_path)
  writefile(['よみ /甲/', 'よみ /乙/'], first_path)
  writefile(['よみ /乙/丙/'], second_path)
  const first = loader.Source.new(first_path)
  const second = loader.Source.new(second_path)
  const forward = loader.Load([first, second])
  const swapped = loader.Load([second, first])
  assert.equals(CandidateTexts(forward['よみ']), ['甲', '乙', '丙'])
  assert.equals(CandidateTexts(swapped['よみ']), ['乙', '丙', '甲'])
}

suite.utf8_bom_and_crlf_are_handled_at_the_file_boundary = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(["\ufeffかな /仮名/\r", "ほか /他/\r"], path)
  const entries = loader.Load([loader.Source.new(path)])
  assert.equals(len(entries), 2)
  assert.equals(CandidateTexts(entries['かな']), ['仮名'])
  assert.equals(CandidateTexts(entries['ほか']), ['他'])
}

suite.last_entry_does_not_require_a_final_newline = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(['かな /仮名/'], path, 'b')
  const entries = loader.Load([loader.Source.new(path)])
  assert.equals(CandidateTexts(entries['かな']), ['仮名'])
}

suite.empty_sources_files_and_comment_only_files_produce_no_entries = (): void => {
  const empty_path = tempname()
  const comments_path = tempname()
  defer delete(empty_path)
  defer delete(comments_path)
  writefile([], empty_path)
  writefile([';; comment', '', '  ', ';; okuri-nasi entries.'], comments_path)
  assert.equals(loader.Load([]), {})
  assert.equals(loader.Load([loader.Source.new(empty_path)]), {})
  assert.equals(loader.Load([loader.Source.new(comments_path)]), {})
}

suite.incremental_database_builder_loads_all_sources_in_order = (): void => {
  const first_path = tempname()
  const second_path = tempname()
  defer delete(first_path)
  defer delete(second_path)
  writefile([';; okuri-nasi entries.', 'かな /仮名/'], first_path)
  writefile([';; okuri-nasi entries.', 'かな /佳名/'], second_path)
  const builder = loader.DatabaseBuilder.new([loader.Source.new(first_path), loader.Source.new(second_path)])
  var steps = 0
  while !builder.IsDone()
    builder.Step(1)
    steps += 1
  endwhile
  assert.equals(steps > 2, true)
  const candidates = builder.Result().Lookup(lookup.CreateQuery('かな', ''))
  assert.equals(mapnew(candidates, (_, candidate) => candidate.text), ['仮名', '佳名'])
}

suite.incremental_reader_preserves_multibyte_text_when_a_chunk_splits_a_line = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(["\ufeff;;" .. repeat('x', 65530) .. "漢字\r", "かな /仮名/"], path, 'b')
  const builder = loader.DatabaseBuilder.new([loader.Source.new(path)])
  const synchronous_candidates = loader.Open([loader.Source.new(path)]).Lookup(lookup.CreateQuery('かな', ''))
  assert.equals(mapnew(synchronous_candidates, (_, candidate) => candidate.text), ['仮名'])
  while !builder.IsDone()
    builder.Step(10)
  endwhile
  const candidates = builder.Result().Lookup(lookup.CreateQuery('かな', ''))
  assert.equals(mapnew(candidates, (_, candidate) => candidate.text), ['仮名'])
}

suite.missing_file_reports_its_path = (): void => {
  const path = tempname()
  var caught = ''
  try
    loader.Load([loader.Source.new(path)])
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: cannot read dictionary: ' .. path .. ': '), 0, caught)
}

suite.invalid_encoded_bytes_report_path_and_encoding = (): void => {
  for [bytes, coding] in [[0zFF, 'utf-8'], [0zA4, 'euc-jp']]
    const path = tempname()
    defer delete(path)
    writefile(bytes, path)
    var caught = ''
    try
      loader.Load([loader.Source.new(path, coding)])
    catch
      caught = v:exception
    endtry
    const prefix = 'caskk: cannot decode dictionary: ' .. path .. ' (' .. coding .. '): '
    assert.equals(stridx(caught, prefix), 0, caught)
  endfor
}

suite.unknown_encoding_is_reported_instead_of_loading_garbled_text = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(['かな /仮名/'], path)
  var caught = ''
  try
    loader.Load([loader.Source.new(path, 'invalid-caskk-encoding')])
  catch
    caught = v:exception
  endtry
  const prefix = 'caskk: cannot decode dictionary: ' .. path .. ' (invalid-caskk-encoding): '
  assert.equals(stridx(caught, prefix), 0, caught)
}

suite.malformed_dictionary_line_is_skipped_and_following_entries_load = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(['かな /仮名/', '壊れた行', 'ほか /他/'], path)
  const entries = loader.Load([loader.Source.new(path)])
  assert.equals(CandidateTexts(entries['かな']), ['仮名'])
  assert.equals(CandidateTexts(entries['ほか']), ['他'])
}

suite.unsupported_okuri_block_is_skipped_and_following_entries_load = (): void => {
  const path = tempname()
  defer delete(path)
  writefile([';; okuri-ari entries.', 'おおk /大/多/[き/大/]/', 'ほか /他/'], path)
  const entries = loader.Load([loader.Source.new(path)])
  assert.equals(has_key(entries, 'おおk'), false)
  assert.equals(CandidateTexts(entries['ほか']), ['他'])
}

suite.loading_is_read_only_and_results_do_not_depend_on_the_file = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(['かな /仮名/'], path)
  const before = readblob(path)
  const entries = loader.Load([loader.Source.new(path)])
  assert.equals(readblob(path), before)
  writefile(['かな /変更/'], path)
  assert.equals(CandidateTexts(entries['かな']), ['仮名'])
  assert.equals(delete(path), 0)
  assert.equals(CandidateTexts(entries['かな']), ['仮名'])
}
