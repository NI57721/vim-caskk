vim9script

# Convert named core KeyTokens to the bytes expected by native Vim input APIs.
# Modified semantics are handled by the dispatch layer, not this conversion.
export def Encode(token: string): string
  if strchars(token) == 1
    return token
  endif
  if token =~# '^<[0-9A-Za-z_-]\+>$'
    # Only a restricted key name enters expr-quote syntax. Literal characters
    # take the branch above, so quotes and command text are never evaluated.
    const encoded: string = eval('"\' .. token .. '"')
    if encoded !=# token
      return encoded
    endif
  endif
  throw 'caskk: unsupported native KeyToken: ' .. token
enddef
