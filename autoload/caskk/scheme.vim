vim9script

import 'caskk/combination_table.vim' as table_types
import 'caskk/output_pattern.vim' as pattern_types
import autoload 'caskk/scheme/output_pattern.vim' as output_pattern

# Compile the consonant/combination definitions without retaining caller data.
# Each dictionary key represents one already normalized KeyToken.
export def Compile(consonants: dict<string>, combinations: dict<string>): table_types.CombinationTable
  final patterns: dict<pattern_types.OutputPattern> = {}
  for [key, pattern] in items(combinations)
    patterns[key] = output_pattern.Parse(pattern)
  endfor

  return table_types.CombinationTable.new(copy(consonants), patterns)
enddef
