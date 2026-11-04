vim9script

import 'caskk/output_pattern.vim' as pattern_types

# Keys are already normalized, individual KeyTokens, including e.g. <C-x>.
# This table contains only the consonant/combination part of an input scheme.
export class CombinationTable
  # Rows are kana.vim consonant identifiers; nasal/sokuon outputs live in symbols.
  const consonants: dict<string>
  const symbols: dict<string>
  const combinations: dict<pattern_types.OutputPattern>

  def new(this.consonants, this.symbols, this.combinations)
  enddef
endclass
