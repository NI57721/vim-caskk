vim9script

import 'caskk/output_pattern.vim' as pattern_types

# pattern is the structured result of scheme/output_pattern.Parse().
# okuri_input is semantic input context, independent of physical key spelling.
# This stage composes scheme output text; kana conversion happens separately.
export def Compose(consonant: string, pattern: pattern_types.OutputPattern,
    okuri_input: bool = false): dict<string>
  const text: string = pattern.text
  const boundary: number = pattern.boundary

  if !okuri_input || boundary == -1
    return {reading: consonant .. text, okuri: ''}
  endif

  return {
    reading: consonant .. strcharpart(text, 0, boundary),
    okuri: strcharpart(text, boundary),
  }
enddef
