vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/numeric.vim' as numeric
import autoload 'caskk/dictionary/index.vim' as index

# DDSKK standard skk-kana-rom-vector; independent of the input scheme.
const OKURI_PREFIXES: dict<string> = {
  'ぁ': 'x', 'あ': 'a', 'ぃ': 'x', 'い': 'i', 'ぅ': 'x', 'う': 'u', 'ぇ': 'x', 'え': 'e',
  'ぉ': 'x', 'お': 'o', 'か': 'k', 'が': 'g', 'き': 'k', 'ぎ': 'g', 'く': 'k', 'ぐ': 'g',
  'け': 'k', 'げ': 'g', 'こ': 'k', 'ご': 'g', 'さ': 's', 'ざ': 'z', 'し': 's', 'じ': 'j',
  'す': 's', 'ず': 'z', 'せ': 's', 'ぜ': 'z', 'そ': 's', 'ぞ': 'z', 'た': 't', 'だ': 'd',
  'ち': 't', 'ぢ': 'd', 'っ': 'x', 'つ': 't', 'づ': 'd', 'て': 't', 'で': 'd', 'と': 't',
  'ど': 'd', 'な': 'n', 'に': 'n', 'ぬ': 'n', 'ね': 'n', 'の': 'n', 'は': 'h', 'ば': 'b',
  'ぱ': 'p', 'ひ': 'h', 'び': 'b', 'ぴ': 'p', 'ふ': 'h', 'ぶ': 'b', 'ぷ': 'p', 'へ': 'h',
  'べ': 'b', 'ぺ': 'p', 'ほ': 'h', 'ぼ': 'b', 'ぽ': 'p', 'ま': 'm', 'み': 'm', 'む': 'm',
  'め': 'm', 'も': 'm', 'ゃ': 'x', 'や': 'y', 'ゅ': 'x', 'ゆ': 'y', 'ょ': 'x', 'よ': 'y',
  'ら': 'r', 'り': 'r', 'る': 'r', 'れ': 'r', 'ろ': 'r', 'ゎ': 'x', 'わ': 'w', 'ゐ': 'x',
  'ゑ': 'x', 'を': 'w', 'ん': 'n',
}

export def CreateQuery(reading: string, okuri: string, small_tsu_okuri_as_t: bool = true): dictionary.Query
  const exact_okuri = strcharpart(okuri, 0, 1)
  if exact_okuri == ''
    return dictionary.Query.new(reading, exact_okuri, numeric.NormalizeLookupReading(reading))
  endif
  if !has_key(OKURI_PREFIXES, exact_okuri)
    throw 'caskk: unsupported SKK okuri: ' .. exact_okuri
  endif
  const prefix = exact_okuri ==# 'っ' && small_tsu_okuri_as_t ? 't' : OKURI_PREFIXES[exact_okuri]
  return dictionary.Query.new(reading, exact_okuri, numeric.NormalizeLookupReading(reading) .. prefix)
enddef

# Search already loaded entries without I/O or inferred morphological filtering.
export def Lookup(entries: dict<dictionary.Entry>, query: dictionary.Query,
    database: index.Database = null_object): list<dictionary.Candidate>
  if database isnot null_object
    return database.Lookup(query)
  endif
  if !has_key(entries, query.lookup_key)
    return []
  endif
  # Ranking or selection may rearrange the returned list without changing sources.
  return copy(entries[query.lookup_key].candidates)
enddef
