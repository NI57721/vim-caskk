vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/index.vim' as dictionary_index
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/numeric.vim' as numeric
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/dictionary/verb.vim' as verb
import autoload 'caskk/dictionary/adjective.vim' as adjective

# Completion retains the matched reading and known okuri, independently of
# conversion's current query. Coarse system okuri keys do not imply a suffix.
export class Candidate
  const query: dictionary.Query
  const okuri: string
  const candidate: dictionary.Candidate
  const text: string
  const tier: string
  const learnable: bool
  const is_stem: bool
  const reading: string

  def new(this.query, this.okuri, this.candidate, this.tier, this.learnable,
      is_stem: bool = false, reading: string = '')
    this.is_stem = is_stem
    this.reading = reading == '' ? query.reading : reading
    this.text = numeric.ExpandPlaceholders(candidate.text, query.reading) .. okuri
  enddef
endclass

# One literal split of the typed reading; no endings are generated.
class StemMatch
  const reading: string
  const source_reading: string
  const okuri: string
  def new(this.reading, this.source_reading, this.okuri)
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
  const _allow_stems: bool
  var _normal_phase: string = ''
  var _stem_length: number = 0
  var _stem_matches: list<StemMatch> = []
  var _stem_targets: dict<bool> = {}
  var _stem_users: dict<list<dictionary.Entry>> = {}
  var _stem_position: number = 0
  var _stem_match: StemMatch = null_object
  var _stem_entry: dictionary.Entry = null_object
  var _stem_sources: list<dictionary_index.PrefixSearch> = []
  var _stem_source: number = 0
  var _stem_user: number = 0
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
      small_tsu_okuri_as_t: bool = true, allow_stem_suffix: bool = true)
    this._entries = entries
    this._preferences = preferences
    this._prefix = prefix
    this._okuri = okuri
    this._database = database
    this._small_tsu = small_tsu_okuri_as_t
    this._allow_stems = allow_stem_suffix
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

  def _MergeStem(entry: dictionary.Entry)
    this._stem_entry = this._stem_entry is null_object ? entry
      : merger.Merge([[this._stem_entry, entry]])[entry.lookup_key]
  enddef

  def _EligibleStem(candidate: dictionary.Candidate): bool
    if this._stem_match.source_reading !=# this._stem_match.reading
      return index(split(join(candidate.annotations, ';'), '[[:space:];]\+'), '@verb-henkaku-k') >= 0
        && verb.AllowsOkuri(candidate, this._stem_match.okuri)
    endif
    return verb.AllowsOkuri(candidate, this._stem_match.okuri)
      || adjective.AllowsOkuri(candidate, this._stem_match.okuri)
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
        if this._allow_stems && this._okuri == '' && strchars(this._prefix) > 1
          this._normal_phase = this._phase
          this._stem_length = strchars(this._prefix) - 1
          this._phase = 'stem-plan'
        endif
      elseif this._phase ==# 'stem-plan'
        if this._stem_length == 0
          this._phase = this._normal_phase
          continue
        endif
        const reading = strcharpart(this._prefix, 0, this._stem_length)
        const suffix = strcharpart(this._prefix, this._stem_length)
        this._stem_matches->add(StemMatch.new(reading, reading, suffix))
        this._stem_targets[reading] = true
        const source_reading = verb.KuruSourceReading(reading)
        if source_reading != ''
          this._stem_matches->add(StemMatch.new(reading, source_reading, suffix))
          this._stem_targets[source_reading] = true
        endif
        this._stem_length -= 1
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
          const matches_prefix = stridx(pair[0], this._prefix) == 0
          if !matches_prefix && !has_key(this._stem_targets, pair[0])
            continue
          endif
          const candidates = this._preferences.RegisteredCandidates(identity)
          if has_key(this._stem_targets, pair[0])
            if !has_key(this._stem_users, pair[0])
              this._stem_users[pair[0]] = []
            endif
            this._stem_users[pair[0]]->add(dictionary.Entry.new(pair[0], candidates))
          endif
          if !matches_prefix
            continue
          endif
          const key = lookup.CreateQuery(pair[0], pair[1], this._small_tsu).lookup_key
          this._Merge(dictionary.Entry.new(key, candidates))
          if index(this._variants[key], pair[1]) < 0
            this._variants[key]->add(pair[1])
          endif
        endif
      elseif this._phase ==# 'keys'
        if this._position >= len(this._keys)
          this._phase = 'stem-start'
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
      elseif this._phase ==# 'emit'
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
      elseif this._phase ==# 'stem-start'
        if this._stem_position >= len(this._stem_matches)
          this._phase = 'done'
          continue
        endif
        this._stem_match = this._stem_matches[this._stem_position]
        this._stem_position += 1
        this._stem_user = 0
        const key = this._stem_match.source_reading
        if this._database is null_object
          this._stem_entry = get(this._entries, key, null_object)
          this._phase = 'stem-users'
        else
          this._stem_entry = null_object
          this._stem_sources = this._database.BeginPlainLookup(key)
          this._stem_source = 0
          this._phase = 'stem-sources'
        endif
      elseif this._phase ==# 'stem-sources'
        if this._stem_source >= len(this._stem_sources)
          this._phase = 'stem-users'
        else
          const source = this._stem_sources[this._stem_source]
          for entry in source.Step(1)
            this._MergeStem(entry)
          endfor
          if source.IsDone()
            this._stem_source += 1
          endif
        endif
      elseif this._phase ==# 'stem-users'
        const entries = get(this._stem_users, this._stem_match.source_reading, [])
        if this._stem_user >= len(entries)
          this._phase = 'stem-rank'
        else
          this._MergeStem(entries[this._stem_user])
          this._stem_user += 1
        endif
      elseif this._phase ==# 'stem-rank'
        if this._stem_entry is null_object
          this._phase = 'stem-start'
          continue
        endif
        this._query = lookup.CreateQuery(this._stem_match.source_reading, '')
        const eligible = filter(copy(this._stem_entry.candidates), (_, candidate) => this._EligibleStem(candidate))
        this._ranked = this._preferences.RankCandidates(this._query, eligible)
        this._candidate = 0
        this._phase = 'stem-emit'
      else
        if this._candidate >= len(this._ranked)
          this._phase = 'stem-start'
          continue
        endif
        const candidate = this._ranked[this._candidate]
        this._candidate += 1
        this._result->add(Candidate.new(this._query, this._stem_match.okuri, candidate,
          this._preferences.GetCandidateTier(this._query, candidate.text), true, true,
          this._stem_match.reading))
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
