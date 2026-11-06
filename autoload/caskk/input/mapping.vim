vim9script

import autoload 'caskk/input/keycode.vim' as keycode
import autoload 'caskk/input/mode.vim' as input_mode

const ACTIONS = [
  'ShowCompletion', 'CancelCompletion', 'Convert', 'NextCandidate', 'PreviousCandidate', 'Commit', 'OpenRegistration',
  'TogglePin', 'ToggleDemote', 'DeleteUserEntry',
  'AbbreviationMode', 'KatakanaMode', 'HalfwidthKatakanaMode', 'FullwidthAlphanumericMode',
]

export def ValidateAction(action: string)
  if index(ACTIONS, action) < 0
    throw 'caskk: unknown binding action: ' .. action
  endif
enddef

export def Lhs(token: string): string
  const translated = keytrans(token)
  if translated =~# '^<[0-9A-Za-z_-]\+>$'
    return keytrans(keycode.Encode(translated))
  endif
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

export def ModeForAction(action: string): string
  if action ==# 'AbbreviationMode'
    return input_mode.ABBREVIATION
  elseif action ==# 'KatakanaMode'
    return input_mode.KATAKANA
  elseif action ==# 'HalfwidthKatakanaMode'
    return input_mode.HALFWIDTH_KATAKANA
  elseif action ==# 'FullwidthAlphanumericMode'
    return input_mode.FULLWIDTH_ALPHANUMERIC
  endif
  return ''
enddef
