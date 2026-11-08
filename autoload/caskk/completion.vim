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

# Completion work is resumable; construction never searches or copies user state.
export class Search
  const _entries: dict<dictionary.Entry>
  const _preferences: user_state.State
  const _prefix: string
  const _okuri: string
  const _database: dictionary_index.Database
  const _small_tsu: bool
  const _revision: number
  var _phase: string = 'init'
  var _sources: list<dictionary_index.PrefixSearch> = []
  var _source: number = 0
  var _entry_keys: list<string> = []
  var _position: number = 0
  var _found: dict<dictionary.Entry> = {}
  var _variants: dict<list<string>> = {}
  var _identities: list<string> = []
  var _keys: list<string> = []
  var _key: string = ''
  var _suffixes: list<string> = []
  var _suffix: string = ''
  var _query: dictionary.Query = null_object
  var _ranked: list<dictionary.Candidate> = []
  var _candidate: number = 0
  var _learnable: bool = false
  var _result: list<Candidate> = []

  def new(entries: dict<dictionary.Entry>, preferences: user_state.State,
      prefix: string, okuri: string = '', database: dictionary_index.Database = null_object,
      small_tsu_okuri_as_t: bool = true)
    this._entries = entries
    this._preferences = preferences
    this._prefix = prefix
    this._okuri = okuri
    this._database = database
    this._small_tsu = small_tsu_okuri_as_t
    this._revision = preferences.Revision()
    if prefix == ''
      this._phase = 'done'
    endif
  enddef

  def IsCurrent(): bool
    return this._revision == this._preferences.Revision()
  enddef

  def IsDone(): bool
    return this._phase ==# 'done'
  enddef

  def Result(): list<Candidate>
    if !this.IsDone()
      throw 'caskk: completion search is not complete'
    endif
    return this._result
  enddef

  def _Merge(entry: dictionary.Entry)
    const key = entry.lookup_key
    if has_key(this._found, key)
      this._found[key] = merger.Merge([[this._found[key], entry]])[key]
    else
      this._found[key] = entry
    endif
    if !has_key(this._variants, key)
      this._variants[key] = []
    endif
  enddef

  def _Suffixes(key: string): list<string>
    const has_okuri = key =~# '[^ -~][a-z]$'
    const reading = has_okuri ? strpart(key, 0, strlen(key) - 1) : key
    if stridx(reading, this._prefix) != 0
      return []
    endif
    if this._okuri != ''
      return has_okuri && lookup.CreateQuery(reading, this._okuri, this._small_tsu).lookup_key ==# key
        ? [this._okuri] : []
    endif
    const known = sort(copy(this._variants[key]))
    return has_okuri && !empty(known) ? known : ['']
  enddef

  def Step(max_work: number): bool
    if max_work <= 0
      throw 'caskk: completion search step must be positive'
    endif
    const started = reltime()
    var work = 0
    while work < max_work && !this.IsDone()
      if work > 0 && reltimefloat(reltime(started)) >= 0.004
        break
      endif
      work += 1
      if this._phase ==# 'init'
        this._identities = sort(this._preferences.RegisteredIdentities())
        if this._database is null_object
          this._entry_keys = keys(this._entries)
          this._phase = 'entries'
        else
          this._sources = this._database.BeginPrefix(this._prefix)
          this._phase = 'sources'
        endif
      elseif this._phase ==# 'sources'
        if this._source >= len(this._sources)
          this._phase = 'users'
          this._position = 0
        else
          const source = this._sources[this._source]
          for entry in source.Step(1)
            this._Merge(entry)
          endfor
          if source.IsDone()
            this._source += 1
          endif
        endif
      elseif this._phase ==# 'entries'
        if this._position >= len(this._entry_keys)
          this._phase = 'users'
          this._position = 0
        else
          const key = this._entry_keys[this._position]
          this._position += 1
          if stridx(key, this._prefix) == 0
            this._Merge(this._entries[key])
          endif
        endif
      elseif this._phase ==# 'users'
        if this._position >= len(this._identities)
          this._keys = sort(keys(this._variants))
          this._position = 0
          this._phase = 'keys'
        else
          const identity = this._identities[this._position]
          this._position += 1
          const pair: list<string> = json_decode(identity)
          if stridx(pair[0], this._prefix) != 0
            continue
          endif
          const key = lookup.CreateQuery(pair[0], pair[1], this._small_tsu).lookup_key
          this._Merge(dictionary.Entry.new(key, this._preferences.RegisteredCandidates(identity)))
          if index(this._variants[key], pair[1]) < 0
            this._variants[key]->add(pair[1])
          endif
        endif
      elseif this._phase ==# 'keys'
        if this._position >= len(this._keys)
          this._phase = 'done'
        else
          this._key = this._keys[this._position]
          this._position += 1
          this._suffixes = copy(this._Suffixes(this._key))
          this._phase = 'rank'
        endif
      elseif this._phase ==# 'rank'
        if empty(this._suffixes)
          this._phase = 'keys'
          continue
        endif
        const suffix = remove(this._suffixes, 0)
        this._suffix = suffix
        const has_okuri = this._key =~# '[^ -~][a-z]$'
        const reading = has_okuri ? strpart(this._key, 0, strlen(this._key) - 1) : this._key
        this._query = dictionary.Query.new(reading, strcharpart(suffix, 0, 1), this._key)
        this._learnable = !has_okuri || suffix != ''
        const candidates = filter(copy(this._found[this._key].candidates),
          (_, candidate) => has_okuri || candidate.has_plain_source)
        this._ranked = this._learnable ? this._preferences.RankCandidates(this._query, candidates) : candidates
        this._candidate = 0
        this._phase = 'emit'
      else
        if this._candidate >= len(this._ranked)
          this._phase = 'rank'
          continue
        endif
        const candidate = this._ranked[this._candidate]
        this._candidate += 1
        const tier = this._learnable
          ? this._preferences.GetCandidateTier(this._query, candidate.text) : 'normal'
        this._result->add(Candidate.new(this._query,
          this._suffix, candidate, tier, this._learnable))
      endif
    endwhile
    return this.IsDone()
  enddef
endclass

export def Prepare(entries: dict<dictionary.Entry>, preferences: user_state.State,
    prefix: string, okuri: string = '', database: dictionary_index.Database = null_object,
    small_tsu_okuri_as_t: bool = true): list<Candidate>
  const search = Search.new(entries, preferences, prefix, okuri, database, small_tsu_okuri_as_t)
  while !search.Step(64)
  endwhile
  return search.Result()
enddef
