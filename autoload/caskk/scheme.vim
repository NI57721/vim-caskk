vim9script

import 'caskk/combination_table.vim' as table_types
import 'caskk/output_pattern.vim' as pattern_types
import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme/kana.vim' as kana
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

# A key sequence is split into Unicode characters. Actual Vim keycodes remain
# atomic; angle-bracket text is ordinary input and is never parsed as notation.
export def InputKeys(sequence: string): list<string>
  final keys: list<string> = []
  var index = 0
  while index < strchars(sequence)
    const character = strcharpart(sequence, index, 1)
    const codepoint = char2nr(character)
    if codepoint == 0x80 && index + 2 < strchars(sequence)
      const encoded = strcharpart(sequence, index, 3)
      const named = keytrans(encoded)
      if named =~# '^<[0-9A-Za-z_-]\+>$'
        keys->add(named)
        index += 3
        continue
      endif
    elseif codepoint < 0x20 || codepoint == 0x7f
      const named = keytrans(character)
      if named =~# '^<[0-9A-Za-z_-]\+>$'
        keys->add(named)
        index += 1
        continue
      endif
    elseif codepoint == 0x20
      keys->add('<Space>')
      index += 1
      continue
    endif
    keys->add(character =~# '^[A-Z]$' ? tolower(character) : character)
    index += 1
  endwhile
  return keys
enddef

# Consonant definitions share the same physical sequence notation.
export def ConsonantKeys(key: string): list<string>
  return InputKeys(key)
enddef

def SpecialKeys(sequence: string): list<string>
  return InputKeys(sequence)
enddef

export def ValidateConsonants(definitions: dict<string>): dict<string>
  final validated: dict<string> = {}
  final sequences: list<list<string>> = []
  for [key, value] in items(definitions)
    const tokens = InputKeys(key)
    if empty(tokens)
      throw 'caskk: invalid input scheme: consonant keys must not be empty'
    endif
    if index(sequences, tokens) >= 0
      throw 'caskk: invalid input scheme: consonant keys resolve to the same key sequence'
    endif
    sequences->add(tokens)
    if !has_key(kana.TABLE.rows, value) && !has_key(kana.TABLE.symbols, value)
      throw 'caskk: invalid input scheme: consonant values must name one kana consonant or output symbol'
    endif
    validated[key] = value
  endfor
  return validated
enddef

export def ValidateCombinations(definitions: dict<string>): dict<string>
  final validated: dict<string> = {}
  for [key, value] in items(definitions)
    const tokens = InputKeys(key)
    if len(tokens) != 1
      throw 'caskk: invalid input scheme: combination keys must be one KeyToken'
    endif
    if has_key(validated, tokens[0])
      throw 'caskk: invalid input scheme: combination keys resolve to the same KeyToken'
    endif
    if empty(value) || index(kana.TABLE.vowels, strcharpart(value, 0, 1)) < 0
      throw 'caskk: invalid input scheme: combination values must start with a kana vowel'
    endif
    if stridx(value, '\') >= 0
      throw 'caskk: invalid input scheme: combination values do not support escapes'
    endif
    for character in str2list(value, true)
      const char = nr2char(character, true)
      if char !=# '*' && char !~# '^[A-Za-z]$'
        throw 'caskk: invalid input scheme: combination values must contain only kana symbols and *'
      endif
    endfor
    const parsed = output_pattern.Parse(value)
    if parsed.boundary == 0
      throw 'caskk: invalid input scheme: combination values cannot start with *'
    endif
    try
      kana.Generate('', parsed)
    catch
      throw 'caskk: invalid input scheme: invalid combination value: ' .. value
    endtry
    validated[tokens[0]] = value
  endfor
  return validated
enddef

export def SpecialDefinitions(definitions: dict<string>): list<SpecialDefinition>
  final specials: list<SpecialDefinition> = []
  for [sequence, output] in items(definitions)
    specials->add(SpecialDefinition.new(SpecialKeys(sequence), output))
  endfor
  return specials
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

  final rows: dict<string> = {}
  final symbols: dict<string> = {}
  for [key, value] in items(consonants)
    if has_key(kana.TABLE.symbols, value)
      symbols[key] = kana.TABLE.symbols[value]
    else
      rows[key] = value
    endif
  endfor
  const table = table_types.CombinationTable.new(rows, symbols, patterns)
  return CompiledScheme.new(table, rules)
enddef
