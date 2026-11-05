vim9script

import autoload 'caskk/dictionary/numeric.vim' as numeric

final suite = themis#suite('numeric dictionary placeholders')
const assert = themis#helper('assert')

suite.numeric_placeholder_types_render_the_same_number_in_multiple_notations = (): void => {
  for [kind, expected] in [
    ['0', '1995'], ['1', '１９９５'], ['2', '一九九五'], ['3', '千九百九十五'],
    ['5', '壱阡九百九拾伍'], ['6', 'MCMXCV'], ['8', '1,995'],
  ]
    assert.equals(numeric.ExpandPlaceholders('#' .. kind, '1995'), expected)
  endfor
}

suite.positional_kanji_omits_zero_places_and_keeps_large_place_units = (): void => {
  assert.equals(numeric.ExpandPlaceholders('#3', '1024'), '千二十四')
  assert.equals(numeric.ExpandPlaceholders('#3', '10002'), '一万二')
}

suite.placeholder_numbers_match_digit_runs_in_order = (): void => {
  assert.equals(numeric.ExpandPlaceholders('#1年#3月', '2026/7'), '２０２６年七月')
}

suite.digit_by_digit_and_positional_styles_handle_zero = (): void => {
  assert.equals(numeric.ExpandPlaceholders('#2', '1002'), '一〇〇二')
  assert.equals(numeric.ExpandPlaceholders('#3', '0'), '〇')
}

suite.numeric_placeholder_zero_preserves_ascii_digits = (): void => {
  assert.equals(numeric.ExpandPlaceholders('#0', '007'), '007')
}

suite.roman_numerals_repeat_thousands_for_values_above_conventional_range = (): void => {
  assert.equals(numeric.ExpandPlaceholders('#6', '2026'), 'MMXXVI')
  assert.equals(numeric.ExpandPlaceholders('#6', '4000'), 'MMMM')
}
