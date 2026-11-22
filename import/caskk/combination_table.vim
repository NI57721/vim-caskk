vim9script

import 'caskk/output_pattern.vim' as pattern_types

# Keys are already normalized, individual KeyTokens, including e.g. <C-x>.
# This table contains only the consonant/combination part of an input scheme.
export class CombinationTable
  # Rows are kana.vim consonant identifiers; nasal/sokuon outputs live in symbols.
  const consonants: dict<string>
  # Consonant keys that emit っ before retaining their row.
  const sokuon: dict<bool>
  const symbols: dict<string>
  const combinations: dict<pattern_types.OutputPattern>

  const n_fallback: bool

  def new(this.consonants, this.symbols, this.combinations, sokuon: dict<bool> = {},
      n_fallback: bool = true)
    this.sokuon = sokuon
    this.n_fallback = n_fallback
  enddef
endclass
