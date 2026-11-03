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

export def Normalize(layout: string, key: string, overrides: dict<string> = {}): input.Event
  for [base, shifted] in items(overrides)
    if shifted ==# key
      return input.Event.new(base, true)
    endif
  endfor

  const keys = get(SHIFTED_KEYS, layout, {})
  if has_key(keys, key)
    const base = keys[key]
    # A user override replaces this base key's built-in shifted symbol.
    return has_key(overrides, base) ? input.Event.new(key) : input.Event.new(base, true)
  endif
  return input.Event.new(key)
enddef
