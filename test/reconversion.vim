vim9script

import 'caskk/reconversion.vim' as reconversion

final suite = themis#suite('recent conversion history')
const assert = themis#helper('assert')

suite.matches_the_longest_confirmed_text_at_the_cursor = (): void => {
  const history = reconversion.History.new(4)
  history.Add('行', 'い', 'く', 'く')
  history.Add('行きます', 'い', 'きます', 'き')
  const match = history.Find('行きますと行く')
  assert.equals(match.text, '行きます')
  assert.equals(match.reading, 'い')
  assert.equals(match.okuri, 'きます')
  assert.equals(match.exact_okuri, 'き')
}

suite.prefers_the_newest_record_when_confirmed_text_has_multiple_readings = (): void => {
  const history = reconversion.History.new(4)
  history.Add('今日', 'きょう')
  history.Add('今日', 'こんにち')
  assert.equals(history.Find('今日は').reading, 'こんにち')
}

suite.keeps_only_the_most_recent_conversion_records = (): void => {
  const history = reconversion.History.new(2)
  history.Add('一', 'いち')
  history.Add('二', 'に')
  history.Add('三', 'さん')
  assert.equals(history.Find('一') is null_object, true)
  assert.equals(history.Find('三').reading, 'さん')
}
