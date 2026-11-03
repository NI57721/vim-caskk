vim9script

import 'caskk/combination_table.vim' as table_types
import 'caskk/output_pattern.vim' as pattern_types
import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme/output_pattern.vim' as output_pattern

# Special inputs are explicit KeyToken lists, not strings to split into keys.
export class SpecialDefinition
  const keys: list<string>
  const output: string

  def new(keys: list<string>, this.output)
    this.keys = copy(keys)
  enddef
endclass

export class CompiledScheme
  const table: table_types.CombinationTable
  const specials: list<special.Rule>

  def new(this.table, this.specials)
  enddef
endclass

# A consonant definition is a sequence of physical keys. Named Vim KeyTokens
# remain atomic; ordinary strings are split into their Unicode characters.
export def ConsonantKeys(key: string): list<string>
  if key =~# '^<[0-9A-Za-z_-]\+>$' || strchars(key) == 1
    return [key]
  endif
  final keys: list<string> = []
  for index in range(0, strchars(key) - 1)
    keys->add(strcharpart(key, index, 1))
  endfor
  return keys
enddef

# Compile all output patterns without retaining caller-owned containers.
# Dictionary keys and special input elements are already normalized KeyTokens.
export def Compile(consonants: dict<string>, combinations: dict<string>,
    specials: list<SpecialDefinition> = []): CompiledScheme
  final patterns: dict<pattern_types.OutputPattern> = {}
  for [key, pattern] in items(combinations)
    const parsed = output_pattern.Parse(pattern)
    if parsed.boundary == 0
      throw 'caskk: combination output cannot start with latent okuri boundary'
    endif
    patterns[key] = parsed
  endfor

  final rules: list<special.Rule> = []
  for definition in specials
    rules->add(special.Rule.new(definition.keys, output_pattern.Parse(definition.output)))
  endfor

  const table = table_types.CombinationTable.new(copy(consonants), patterns)
  return CompiledScheme.new(table, rules)
enddef
