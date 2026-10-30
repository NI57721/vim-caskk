vim9script

import autoload 'caskk/input/normalize.vim' as normalize
import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme/output_pattern.vim' as output_pattern

final suite = themis#suite('input normalization')
const assert = themis#helper('assert')

suite.ascii_uppercase_becomes_modified_lowercase = (): void => {
  const normalizer = normalize.Normalizer.new()
  for code in range(char2nr('A'), char2nr('Z'))
    const events = normalizer.Feed(nr2char(code))
    assert.equals(len(events), 1)
    assert.equals(events[0].key, nr2char(code + 32))
    assert.equals(events[0].modified, true)
  endfor
}

suite.other_tokens_are_preserved = (): void => {
  const normalizer = normalize.Normalizer.new()
  for key in ['a', '1', ';', '<C-x>', '<M-j>', 'あ', 'Ä', 'AB']
    const events = normalizer.Feed(key)
    assert.equals(len(events), 1)
    assert.equals(events[0].key, key)
    assert.equals(events[0].modified, false)
  endfor
}

suite.sticky_key_modifies_only_the_next_token = (): void => {
  const normalizer = normalize.Normalizer.new(';')
  assert.equals(normalizer.Feed(';'), [])
  const modified = normalizer.Feed('k')
  assert.equals(modified[0].key, 'k')
  assert.equals(modified[0].modified, true)
  const normal = normalizer.Feed('l')
  assert.equals(normal[0].key, 'l')
  assert.equals(normal[0].modified, false)
}

suite.sticky_key_accepts_arbitrary_key_tokens = (): void => {
  const normalizer = normalize.Normalizer.new('<C-x>')
  for key in ['1', '<M-j>', 'あ']
    assert.equals(normalizer.Feed('<C-x>'), [])
    const events = normalizer.Feed(key)
    assert.equals(events[0].key, key)
    assert.equals(events[0].modified, true)
  endfor
  assert.equals(normalizer.Feed(';')[0].modified, false)
}

suite.uppercase_consumes_pending_sticky_modifier = (): void => {
  const normalizer = normalize.Normalizer.new(';')
  normalizer.Feed(';')
  const events = normalizer.Feed('K')
  assert.equals(events[0].key, 'k')
  assert.equals(events[0].modified, true)
  assert.equals(normalizer.Feed('l')[0].modified, false)
}

suite.reset_clears_pending_sticky_modifier = (): void => {
  const normalizer = normalize.Normalizer.new(';')
  normalizer.Feed(';')
  normalizer.Reset()
  assert.equals(normalizer.Feed('k')[0].modified, false)
}

suite.normalizers_do_not_share_pending_state = (): void => {
  const first = normalize.Normalizer.new(';')
  const second = normalize.Normalizer.new(';')
  first.Feed(';')
  assert.equals(first.Feed('k')[0].modified, true)
  assert.equals(second.Feed('k')[0].modified, false)
}

suite.uppercase_and_sticky_input_have_same_special_semantics = (): void => {
  const rules = [special.Rule.new(['a', 'b', 'c'], output_pattern.Parse('か*ける'))]
  for keys in [['A', 'B', 'c'], [';', 'a', ';', 'b', 'c']]
    const normalizer = normalize.Normalizer.new(';')
    var pending = []
    var result: dict<any> = {}
    for key in keys
      const events = normalizer.Feed(key)
      if empty(events)
        continue
      endif
      result = special.MatchEvents(rules, pending + events)
      assert.equals(result.replay, [])
      pending = result.pending
    endfor
    assert.equals(special.Compose(result.output, result.events),
      {start_conversion: true, reading: 'か', okuri: 'ける'})
  endfor
}
