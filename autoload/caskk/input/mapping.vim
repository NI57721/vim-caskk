vim9script

import autoload 'caskk/input/keycode.vim' as keycode

const ACTIONS = ['StartConversion', 'NextCandidate', 'PreviousCandidate', 'Commit']

export def ValidateAction(action: string)
  if index(ACTIONS, action) < 0
    throw 'caskk: unknown binding action: ' .. action
  endif
enddef

export def Lhs(token: string): string
  if token == ' '
    return '<Space>'
  elseif token == '|'
    return '<Bar>'
  elseif token == '\'
    return '<Bslash>'
  elseif token == '<'
    return '<lt>'
  elseif token =~# '^<[0-9A-Za-z_-]\+>$'
    return keytrans(keycode.Encode(token))
  elseif strchars(token) == 1 && char2nr(token) >= 0x21
    return token
  endif
  throw 'caskk: unsupported mapping KeyToken: ' .. token
enddef
