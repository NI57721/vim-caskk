vim9script

import 'caskk/input.vim' as input

# Vim supplies printable characters, so shifted punctuation must be converted
# back to the unshifted key plus Modified before IME semantics are applied.
const SHIFTED_KEYS = {
  US: {
    '!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7',
    '*': '8', '(': '9', ')': '0', '_': '-', '+': '=', '{': '[', '}': ']',
    '|': '\', ':': ';', '"': "'", '<': ',', '>': '.', '?': '/', '~': '`',
  },
  JIS: {
    '!': '1', '"': '2', '#': '3', '$': '4', '%': '5', '&': '6', "'": '7',
    '(': '8', ')': '9', '?': '0', '=': '-', '~': '^', '|': '\', '`': '@',
    '{': '[', '}': ']', '+': ';', '*': ':', '<': ',', '>': '.',
  },
}

export def Normalize(layout: string, key: string): input.Event
  const keys = get(SHIFTED_KEYS, layout, {})
  return has_key(keys, key) ? input.Event.new(keys[key], true) : input.Event.new(key)
enddef
