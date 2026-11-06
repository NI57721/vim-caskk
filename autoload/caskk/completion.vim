vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/index.vim' as dictionary_index
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/numeric.vim' as numeric
import autoload 'caskk/user_state.vim' as user_state

# Completion retains the matched reading and known okuri, independently of
# conversion's current query. Coarse system okuri keys do not imply a suffix.
export class Candidate
  const query: dictionary.Query
  const okuri: string
  const candidate: dictionary.Candidate
  const text: string
  const tier: string
  const learnable: bool

  def new(this.query, this.okuri, this.candidate, this.tier, this.learnable)
    this.text = numeric.ExpandPlaceholders(candidate.text, query.reading) .. okuri
  enddef
endclass

export def Prepare(entries: dict<dictionary.Entry>, preferences: user_state.State,
    prefix: string, okuri: string = '', database: dictionary_index.Database = null_object,
    small_tsu_okuri_as_t: bool = true): list<Candidate>
  if prefix == ''
    return []
  endif
  final found = database is null_object
    ? filter(copy(entries), (_, entry) => stridx(entry.lookup_key, prefix) == 0)
    : database.Prefix(prefix)
  final variants: dict<list<string>> = {}
  for key in keys(found)
    variants[key] = []
  endfor
  for [identity, registered] in items(preferences.GetSnapshot().entries)
    const pair: list<string> = json_decode(identity)
    if stridx(pair[0], prefix) != 0
      continue
    endif
    const key = lookup.CreateQuery(pair[0], pair[1], small_tsu_okuri_as_t).lookup_key
    const source = has_key(found, key) ? found[key].candidates : []
    found[key] = merger.Merge([[dictionary.Entry.new(key, source),
      dictionary.Entry.new(key, registered)]])[key]
    if !has_key(variants, key)
      variants[key] = []
    endif
    if index(variants[key], pair[1]) < 0
      variants[key]->add(pair[1])
    endif
  endfor
  final results: list<Candidate> = []
  for key in sort(keys(variants))
    # ASCII abbreviations ending in letters are not okuri entries.
    const has_okuri = key =~# '[^ -~][a-z]$'
    const reading = has_okuri ? strpart(key, 0, strlen(key) - 1) : key
    if stridx(reading, prefix) != 0
      continue
    endif
    final suffixes: list<string> = []
    if okuri != ''
      if !has_okuri || lookup.CreateQuery(reading, okuri, small_tsu_okuri_as_t).lookup_key !=# key
        continue
      endif
      suffixes->add(okuri)
    elseif has_okuri
      suffixes->extend(sort(copy(variants[key])))
      if empty(suffixes)
        suffixes->add('')
      endif
    else
      suffixes->add('')
    endif
    for suffix in suffixes
      const query = dictionary.Query.new(reading, strcharpart(suffix, 0, 1), key)
      const candidates = has_key(found, key) ? found[key].candidates : []
      const learnable = !has_okuri || suffix != ''
      const ranked = learnable ? preferences.Rank(query, candidates) : candidates
      for candidate in ranked
        results->add(Candidate.new(query, suffix, candidate,
          learnable ? preferences.GetCandidateTier(query, candidate.text) : 'normal', learnable))
      endfor
    endfor
  endfor
  return results
enddef
