vim9script

import 'caskk/output_pattern.vim' as pattern_types
import 'caskk/combination_table.vim' as table_types
import autoload 'caskk/scheme/kana.vim' as kana

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

# Resolve individual KeyTokens and generate kana before splitting okuri.
# The caller decides whether this input is interpreted as okuri input.
export def ComposeKeys(table: table_types.CombinationTable, consonant_key: string,
    combination_key: string, okuri_input: bool = false): dict<string>
  if !has_key(table.consonants, consonant_key)
    throw 'caskk: unknown consonant key: ' .. consonant_key
  endif
  if !has_key(table.combinations, combination_key)
    throw 'caskk: unknown combination key: ' .. combination_key
  endif

  const pattern = kana.Generate(table.consonants[consonant_key], table.combinations[combination_key])
  return Compose('', pattern, okuri_input)
enddef
