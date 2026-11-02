vim9script

import 'caskk/output_pattern.vim' as pattern_types
import 'caskk/combination_table.vim' as table_types
import 'caskk/input.vim' as input
import 'caskk/composition.vim' as composition
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

# Interpret an already generated consonant/combination output.
# A Modified consonant in Preedit starts okuri before the whole syllable.
# Otherwise a Modified combination activates its latent output boundary.
export def ComposeEvents(pattern: pattern_types.OutputPattern, events: list<input.Event>,
    in_preedit: bool = false): composition.Result
  if len(events) == 1
    if pattern.boundary != -1
      throw 'caskk: standalone combination cannot activate latent okuri boundary'
    endif
    return composition.Result.new(!in_preedit, pattern.text, '', false)
  endif
  if len(events) != 2
    throw 'caskk: combination composition requires exactly two input events'
  endif
  const first_modified = events[0].modified
  const second_modified = events[1].modified
  if in_preedit && first_modified
    return composition.Result.new(false, '', pattern.text, true)
  endif

  const composed = Compose('', pattern, second_modified)
  return composition.Result.new(!in_preedit && (first_modified || second_modified),
    composed.reading, composed.okuri, second_modified && pattern.boundary != -1)
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
