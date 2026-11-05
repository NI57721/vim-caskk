vim9script

import autoload 'caskk/dictionary/parser.vim' as parser

final suite = themis#suite('SKK dictionary line parser')
const assert = themis#helper('assert')

suite.candidate_order_and_duplicates_are_preserved = (): void => {
  const entry = parser.ParseLine('かんじ /漢字/感じ/漢字/')
  assert.equals(entry.lookup_key, 'かんじ')
  assert.equals(len(entry.candidates), 3)
  assert.equals(entry.candidates[0].text, '漢字')
  assert.equals(entry.candidates[1].text, '感じ')
  assert.equals(entry.candidates[2].text, '漢字')
}

suite.first_semicolon_separates_text_from_annotation = (): void => {
  const entry = parser.ParseLine('かんじ /漢字;文字/感じ;感覚;補足/')
  assert.equals(entry.candidates[0].text, '漢字')
  assert.equals(entry.candidates[0].annotations, ['文字'])
  assert.equals(entry.candidates[1].text, '感じ')
  assert.equals(entry.candidates[1].annotations, ['感覚;補足'])
}

suite.absent_or_empty_annotation_produces_an_empty_list = (): void => {
  const entry = parser.ParseLine('かな /仮名/カナ;/')
  assert.equals(entry.candidates[0].annotations, [])
  assert.equals(entry.candidates[1].text, 'カナ')
  assert.equals(entry.candidates[1].annotations, [])
}

suite.okuri_lookup_key_is_preserved_without_morphological_inference = (): void => {
  const entry = parser.ParseLine('いk /行/往/')
  assert.equals(entry.lookup_key, 'いk')
  assert.equals(entry.candidates[0].text, '行')
  assert.equals(entry.candidates[1].text, '往')
}

suite.ascii_lookup_key_and_internal_and_surrounding_candidate_spaces_are_preserved = (): void => {
  const entry = parser.ParseLine('c++ /C++/C plus plus/ leading /')
  assert.equals(entry.lookup_key, 'c++')
  assert.equals(entry.candidates[0].text, 'C++')
  assert.equals(entry.candidates[1].text, 'C plus plus')
  assert.equals(entry.candidates[2].text, ' leading ')
}

suite.blank_lines_and_comments_are_skipped = (): void => {
  for line in ['', '  ', "\t", ';; comment', ';; okuri-ari entries.', ';; okuri-nasi entries.', '  ;; comment']
    assert.equals(parser.ParseLine(line) is null_object, true)
  endfor
}

suite.scheme_markers_and_backslashes_are_literal_dictionary_text = (): void => {
  const entry = parser.ParseLine('きごう /星*;注\釈/か\*な/')
  assert.equals(entry.candidates[0].text, '星*')
  assert.equals(entry.candidates[0].annotations, ['注\釈'])
  assert.equals(entry.candidates[1].text, 'か\*な')
}

suite.unicode_text_is_preserved_without_normalization = (): void => {
  const entry = parser.ParseLine("かな /か\u3099/が/")
  assert.equals(entry.candidates[0].text, "か\u3099")
  assert.equals(entry.candidates[1].text, 'が')
}

suite.encoded_candidate_text_is_preserved_without_decoding = (): void => {
  const entry = parser.ParseLine('すらっしゅ /(concat "\057")/')
  assert.equals(entry.candidates[0].text, '(concat "\057")')
  assert.equals(entry.candidates[0].annotations, [])
}

suite.personal_dictionary_okuri_blocks_are_rejected = (): void => {
  var caught = ''
  try
    parser.ParseLine('おおk /大/多/[き/大/]/')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: unsupported SKK okuri block')
}

suite.balanced_square_brackets_are_preserved_in_system_candidates = (): void => {
  const entry = parser.ParseLine('あれきさんどろす /[Alexandros]/')
  assert.equals(entry.candidates[0].text, '[Alexandros]')
}

suite.malformed_entries_are_rejected = (): void => {
  for line in [
    'かな',
    ' /仮名/',
    'かな 仮名/',
    'かな /仮名',
    'かな /',
    'かな //',
    'かな /仮名//カナ/',
    'かな /;注釈/',
    'かな /仮名/ trailing',
    "かな /仮名/\nほか /他/",
    "かな /仮名/\r",
  ]
    var caught = ''
    try
      parser.ParseLine(line)
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: invalid SKK dictionary entry')
  endfor
}
