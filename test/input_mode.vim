vim9script

import autoload 'caskk/input/mode.vim' as input_mode

final suite = themis#suite('input modes')
const assert = themis#helper('assert')

suite.katakana_mode_transliterates_kana_and_preserves_kanji = (): void => {
  assert.equals(input_mode.Render('これが欲しい', input_mode.KATAKANA), 'コレガ欲シイ')
}

suite.halfwidth_katakana_mode_transliterates_voiced_kana = (): void => {
  assert.equals(input_mode.Render('これが欲しい', input_mode.HALFWIDTH_KATAKANA), 'ｺﾚｶﾞ欲ｼｲ')
}

suite.fullwidth_alphanumeric_mode_maps_ascii_letters_digits_punctuation_and_space = (): void => {
  assert.equals(input_mode.Render('I like apples! Do you?', input_mode.FULLWIDTH_ALPHANUMERIC),
    'Ｉ　ｌｉｋｅ　ａｐｐｌｅｓ！　Ｄｏ　ｙｏｕ？')
}

suite.non_kana_text_is_preserved_by_katakana_modes = (): void => {
  assert.equals(input_mode.Render('漢字ABC。', input_mode.KATAKANA), '漢字ABC。')
  assert.equals(input_mode.Render('漢字ABC。', input_mode.HALFWIDTH_KATAKANA), '漢字ABC｡')
}

suite.same_mode_trigger_returns_to_hiragana_and_other_mode_switches_directly = (): void => {
  assert.equals(input_mode.Transition(input_mode.HIRAGANA, input_mode.KATAKANA), input_mode.KATAKANA)
  assert.equals(input_mode.Transition(input_mode.KATAKANA, input_mode.KATAKANA), input_mode.HIRAGANA)
  assert.equals(input_mode.Transition(input_mode.KATAKANA, input_mode.FULLWIDTH_ALPHANUMERIC),
    input_mode.FULLWIDTH_ALPHANUMERIC)
}
