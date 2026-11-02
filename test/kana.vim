vim9script

import autoload 'caskk/scheme/output_pattern.vim' as output_pattern
import autoload 'caskk/scheme/kana.vim' as kana

final suite = themis#suite('scheme kana generation')
const assert = themis#helper('assert')

# Use the shared specification data to exercise row and symbol expansion.
suite.defined_rows_and_vowels = (): void => {
  for [row, outputs] in items(kana.TABLE.rows)
    for index in range(len(kana.TABLE.vowels))
      if outputs[index] == ''
        continue
      endif
      const result = kana.Generate(row, output_pattern.Parse(kana.TABLE.vowels[index]))
      assert.equals(result.text, outputs[index])
      assert.equals(result.boundary, -1)
    endfor
  endfor
}

suite.leading_vowel_uses_consonant_row = (): void => {
  const result = kana.Generate('k', output_pattern.Parse('a'))
  assert.equals(result.text, 'か')
  assert.equals(result.boundary, -1)
}

suite.vowels_without_consonant = (): void => {
  const result = kana.Generate('', output_pattern.Parse('aiueo'))
  assert.equals(result.text, 'あいうえお')
  assert.equals(result.boundary, -1)
}

suite.tail_vowels_are_in_the_vowel_row = (): void => {
  const result = kana.Generate('n', output_pattern.Parse('aiueo'))
  assert.equals(result.text, 'ないうえお')
}

suite.small_kana_rows = (): void => {
  assert.equals(kana.Generate('x', output_pattern.Parse('a')).text, 'ぁ')
  assert.equals(kana.Generate('xy', output_pattern.Parse('a')).text, 'ゃ')
  assert.equals(kana.Generate('xy', output_pattern.Parse('u')).text, 'ゅ')
  assert.equals(kana.Generate('xy', output_pattern.Parse('o')).text, 'ょ')
  assert.equals(kana.Generate('xw', output_pattern.Parse('a')).text, 'ゎ')
}

suite.shortened_i_and_small_kana_boundaries = (): void => {
  const palatalized = kana.Generate('ky', output_pattern.Parse('i*iN'))
  assert.equals(palatalized.text, 'きいん')
  assert.equals(palatalized.boundary, 1)
  const small = kana.Generate('xy', output_pattern.Parse('a*iN'))
  assert.equals(small.text, 'ゃいん')
  assert.equals(small.boundary, 1)
}

suite.undefined_small_kana_is_rejected = (): void => {
  for [row, vowel] in [['xy', 'i'], ['xy', 'e'], ['xw', 'i'], ['xw', 'u'], ['xw', 'e'], ['xw', 'o']]
    var caught = ''
    try
      kana.Generate(row, output_pattern.Parse(vowel))
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: undefined kana: ' .. row .. vowel)
  endfor
}

suite.nasal_and_small_tsu_symbols = (): void => {
  for [symbol, expected] in items(kana.TABLE.symbols)
    for row in keys(kana.TABLE.rows)
      const result = kana.Generate(row, output_pattern.Parse(symbol))
      assert.equals(result.text, expected)
      assert.equals(result.boundary, -1)
    endfor
  endfor
  assert.equals(kana.Generate('', output_pattern.Parse('aTi')).text, 'あっい')
  assert.equals(kana.Generate('n', output_pattern.Parse('a*iN')).text, 'ないん')
}

suite.boundaries_follow_generated_character_offsets = (): void => {
  const ordinary = kana.Generate('n', output_pattern.Parse('a*iN'))
  assert.equals(ordinary.text, 'ないん')
  assert.equals(ordinary.boundary, 1)
  const palatalized = kana.Generate('ky', output_pattern.Parse('a*iN'))
  assert.equals(palatalized.text, 'きゃいん')
  assert.equals(palatalized.boundary, 2)
  const extended = kana.Generate('v', output_pattern.Parse('eNT*a'))
  assert.equals(extended.text, 'ゔぇんっあ')
  assert.equals(extended.boundary, 4)
}

suite.okuri_suffix_is_generated_from_roman_prefix = (): void => {
  const result = kana.Generate('k', output_pattern.Parse('e*tu'))
  assert.equals(result.text, 'けつ')
  assert.equals(result.boundary, 1)
}

suite.literal_markers_and_unicode_survive = (): void => {
  const result = kana.Generate('ky', output_pattern.Parse('a\*\\*い'))
  assert.equals(result.text, 'きゃ*\い')
  assert.equals(result.boundary, 4)
}

suite.boundaries_at_edges = (): void => {
  assert.equals(kana.Generate('ky', output_pattern.Parse('a*')).boundary, 2)
  const empty = kana.Generate('', output_pattern.Parse('*'))
  assert.equals(empty.text, '')
  assert.equals(empty.boundary, 0)
}

suite.empty_output = (): void => {
  const result = kana.Generate('', output_pattern.Parse(''))
  assert.equals(result.text, '')
  assert.equals(result.boundary, -1)
}

suite.n_is_not_a_nasal_alias = (): void => {
  var caught = ''
  try
    kana.Generate('', output_pattern.Parse('an'))
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: invalid combination symbol: n')
}

suite.symbols_are_case_sensitive = (): void => {
  for symbol in ['n', 't']
    var caught = ''
    try
      kana.Generate('', output_pattern.Parse(symbol))
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: invalid combination symbol: ' .. symbol)
  endfor
  assert.equals(kana.Generate('', output_pattern.Parse(';')).text, ';')
}

suite.unknown_row_is_rejected = (): void => {
  var caught = ''
  try
    kana.Generate('unknown', output_pattern.Parse('a'))
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: unknown consonant row: unknown')
}
