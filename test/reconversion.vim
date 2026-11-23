vim9script

import 'caskk/reconversion.vim' as reconversion

final suite = themis#suite('recent conversion history')
const assert = themis#helper('assert')

suite.matches_from_the_start_and_inside_but_excludes_the_end = (): void => {
  const history = reconversion.History.new()
  history.Add('書く', 'か', 'く', 'く')
  for cursor_byte in [3, 6]
    const match = history.Find('前書く後', cursor_byte)
    assert.equals(match.start_byte, 3)
    assert.equals(match.record.text, '書く')
    assert.equals(match.record.reading, 'か')
    assert.equals(match.record.okuri, 'く')
    assert.equals(match.record.exact_okuri, 'く')
  endfor
  assert.equals(history.Find('前書く後', 0) is null_object, true)
  assert.equals(history.Find('前書く後', 9) is null_object, true)
}

suite.prefers_the_most_characters_even_when_the_match_uses_fewer_bytes = (): void => {
  const history = reconversion.History.new()
  history.Add('界ab', 'longer')
  history.Add('界界', 'shorter')
  const match = history.Find('界界ab', 3)
  assert.equals(match.record.text, '界ab')
  assert.equals(match.start_byte, 3)
}

suite.prefers_the_newest_record_for_equal_length_overlaps = (): void => {
  const history = reconversion.History.new()
  history.Add('本語', 'older')
  history.Add('日本', 'newer')
  const match = history.Find('日本語', 3)
  assert.equals(match.record.reading, 'newer')
  assert.equals(match.start_byte, 0)
}

suite.prefers_the_closest_start_for_overlapping_occurrences_of_one_record = (): void => {
  const history = reconversion.History.new()
  history.Add('人人', 'ひとびと')
  assert.equals(history.Find('人人人', 3).start_byte, 3)
}

suite.keeps_only_the_most_recent_conversion_records = (): void => {
  const history = reconversion.History.new(2)
  history.Add('一', 'いち')
  history.Add('二', 'に')
  history.Add('三', 'さん')
  assert.equals(history.Find('一', 0) is null_object, true)
  assert.equals(history.Find('三', 0).record.reading, 'さん')
}
