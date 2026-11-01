vim9script

import autoload 'caskk/input/keycode.vim' as keycode

final suite = themis#suite('native key encoding')
const assert = themis#helper('assert')

suite.named_tokens_are_encoded_as_native_vim_keys = (): void => {
  assert.equals(keycode.Encode('<F10>'), "\<F10>")
  assert.equals(keycode.Encode('<C-x>'), "\<C-x>")
  assert.equals(keycode.Encode('<Left>'), "\<Left>")
  assert.equals(keycode.Encode('<CR>'), "\<CR>")
  assert.equals(keycode.Encode('<Space>'), ' ')
  assert.equals(keycode.Encode('<lt>'), '<')
}

suite.literal_characters_are_not_interpreted_as_expressions = (): void => {
  for token in ['a', 'あ', '<', '|', "'", '"', '\', ' ']
    assert.equals(keycode.Encode(token), token)
  endfor
}

suite.unknown_names_and_expression_fragments_are_rejected = (): void => {
  for token in ['', 'AB', '<CaskkUnknown>', '<F10>"|quit', '<F10><CR>']
    var caught = ''
    try
      keycode.Encode(token)
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: unsupported native KeyToken: ' .. token)
  endfor
}
