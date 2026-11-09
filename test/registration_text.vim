vim9script
import autoload 'caskk/registration/text.vim' as registration_text
final suite = themis#suite('registration draft parsing')
const assert = themis#helper('assert')
suite.first_separator_preserves_annotation = (): void => {
  for [draft, body, annotation] in [['語', '語', ''], ['語;', '語', ''],
      ['美し;説明;@adj', '美し', '説明;@adj'], [';注釈', '', '注釈'],
      [' 語 ; 注釈 ', ' 語 ', ' 注釈 ']]
    const result = registration_text.Parse(draft)
    assert.equals(result.text, body)
    assert.equals(result.annotations, annotation == '' ? [] : [annotation])
  endfor
}
