vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/numeric.vim' as numeric
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/config.vim' as configuration

import autoload 'caskk/dictionary/verb.vim' as verb
import autoload 'caskk/dictionary/adjective.vim' as adjective
import autoload 'caskk/dictionary/stem.vim' as stem

# Conversion and tagged completion share the source identity and kuru variants.
export def LearnCandidate(preferences: user_state.State, query: dictionary.Query,
    candidate: dictionary.Candidate, is_stem: bool, direct: bool)
  final variants: list<string> = []
  if is_stem && query.reading =~# 'く$'
      && index(split(join(candidate.annotations, ';'), '[[:space:];]\+'), '@verb-henkaku-k') >= 0
    const prefix = strcharpart(query.reading, 0, strchars(query.reading) - 1)
    variants->extend([prefix .. 'こ', prefix .. 'き'])
  endif
  preferences.Learn(query, candidate.text, variants, direct)
enddef

class CandidateSource
  const candidate: dictionary.Candidate
  const marker: string

  def new(this.candidate, this.marker)
  enddef

  def PreferenceQuery(query: dictionary.Query): dictionary.Query
    if this.candidate.source_reading != ''
      return lookup.CreateQuery(this.candidate.source_reading, '')
    endif
    return this.marker == '' ? query : lookup.CreateQuery(query.reading, '')
  enddef
endclass

# Keep the ranked source identities behind each distinct commit string.
export class Candidates
  const query: dictionary.Query
  const okuri: string
  const experimental_count: number
  const markers: list<string> = []
  const experimental_flags: list<bool> = []
  const candidates: list<dictionary.Candidate>
  const _texts: list<string> = []
  const _annotations: list<list<string>> = []
  const _sources: list<list<CandidateSource>> = []

  def new(this.query, this.okuri, candidates: list<dictionary.Candidate>, markers: list<string> = [])
    final positions: dict<number> = {}
    final representatives: list<dictionary.Candidate> = []
    var experimental_count = 0
    for index in range(len(candidates))
      const candidate = candidates[index]
      const text = numeric.ExpandPlaceholders(candidate.text, this.query.reading) .. this.okuri
      const source = CandidateSource.new(candidate, get(markers, index, ''))
      if !has_key(positions, text)
        positions[text] = len(this._texts)
        this._texts->add(text)
        this._sources->add([])
        this._annotations->add([])
        representatives->add(candidate)
        if !empty(markers)
          this.markers->add(source.marker)
          this.experimental_flags->add(source.marker != '')
        endif
        if source.marker != ''
          experimental_count += 1
        endif
      endif
      const position = positions[text]
      this._sources[position]->add(source)
      for annotation in candidate.annotations
        if index(this._annotations[position], annotation) < 0
          this._annotations[position]->add(annotation)
        endif
      endfor
    endfor
    this.candidates = representatives
    this.experimental_count = experimental_count
  enddef

  def PreferenceQuery(index: number): dictionary.Query
    return this._sources[index][0].PreferenceQuery(this.query)
  enddef

  def IsExperimental(index: number): bool
    return this._sources[index][0].marker != ''
  enddef

  def DisplayAt(index: number): string
    return this.TextAt(index) .. this._sources[index][0].marker
  enddef

  def TextAt(index: number): string
    if index < 0 || index >= len(this.candidates)
      throw 'caskk: conversion candidate index out of range: ' .. index
    endif
    return this._texts[index]
  enddef

  def AnnotationsAt(index: number): list<string>
    return copy(this._annotations[index])
  enddef

  def SourcesAt(index: number): list<CandidateSource>
    return copy(this._sources[index])
  enddef
endclass

# Presentation data only. Index is zero-based; text includes display okuri.
export class CandidateInfo
  const index: number
  const count: number
  const text: string
  const annotations: list<string>
  const tier: string

  def new(this.index, this.count, this.text, annotations: list<string>, this.tier)
    this.annotations = copy(annotations)
  enddef
endclass

# Presentation data for the ranked candidates and the current selection.
export class CandidateListInfo
  const selected_index: number
  const candidates: list<CandidateInfo>

  def new(this.selected_index, candidates: list<CandidateInfo>)
    this.candidates = copy(candidates)
  enddef
endclass

export def PageStart(index: number, size: number): number
  return index / size * size
enddef

# One selection lifecycle. Buffer changes and returning to Preedit are handled
# by the caller; Cancel returns the original reading text to display there.
export class Selection
  const _prepared: Candidates
  const _preferences: user_state.State
  var _index: number = 0
  public var rank_action: string = ''
  var _active: bool = true

  def new(prepared: Candidates, preferences: user_state.State)
    if empty(prepared.candidates)
      throw 'caskk: cannot select from empty conversion candidates'
    endif
    this._prepared = prepared
    this._preferences = preferences
  enddef

  def _CheckActive()
    if !this._active
      throw 'caskk: conversion selection is already closed'
    endif
  enddef

  def IsActive(): bool
    return this._active
  enddef

  def Index(): number
    return this._index
  enddef

  def CurrentText(): string
    this._CheckActive()
    return this._prepared.TextAt(this._index)
  enddef

  def GetInfo(): CandidateInfo
    this._CheckActive()
    const candidate = this._prepared.candidates[this._index]
    return CandidateInfo.new(this._index, len(this._prepared.candidates),
      this._prepared.DisplayAt(this._index), this._prepared.AnnotationsAt(this._index),
      this._preferences.GetCandidateTier(this._prepared.PreferenceQuery(this._index), candidate.text))
  enddef

  def GetCandidatesInfo(): CandidateListInfo
    this._CheckActive()
    final candidates: list<CandidateInfo> = []
    const count = len(this._prepared.candidates)
    for index in range(0, count - 1)
      const candidate = this._prepared.candidates[index]
      candidates->add(CandidateInfo.new(index, count, this._prepared.DisplayAt(index), this._prepared.AnnotationsAt(index),
        this._preferences.GetCandidateTier(this._prepared.PreferenceQuery(index), candidate.text)))
    endfor
    return CandidateListInfo.new(this._index, candidates)
  enddef

  def CanDeleteUserEntry(): bool
    this._CheckActive()
    const query = this._prepared.query
    for source in this._prepared.SourcesAt(this._index)
      const text = source.candidate.text
      if source.marker == ''
        if this._preferences.HasEntryForLookup(query, text)
          return true
        endif
      elseif !empty(stem.RegisteredQueries(this._preferences, source.PreferenceQuery(query).reading, text))
        return true
      endif
    endfor
    return false
  enddef

  def DeleteUserEntry()
    this._CheckActive()
    const query = this._prepared.query
    for source in this._prepared.SourcesAt(this._index)
      const text = source.candidate.text
      if source.marker == ''
        this._preferences.DeleteEntryForLookup(query, text)
      else
        for registered in stem.RegisteredQueries(this._preferences, source.PreferenceQuery(query).reading, text)
          this._preferences.DeleteEntry(registered, text)
        endfor
      endif
    endfor
  enddef

  def IsExperimental(): bool
    return this._prepared.IsExperimental(this._index)
  enddef

  def TogglePin(index: number = -1): string
    this._CheckActive()
    const target = index < 0 ? this._index : index
    const text = this._prepared.candidates[target].text
    return this._preferences.TogglePin(this._prepared.PreferenceQuery(target), text)
  enddef

  def ToggleDemote(index: number = -1): string
    this._CheckActive()
    const target = index < 0 ? this._index : index
    const text = this._prepared.candidates[target].text
    return this._preferences.ToggleDemote(this._prepared.PreferenceQuery(target), text)
  enddef

  def Select(index: number): string
    this._CheckActive()
    const text = this._prepared.TextAt(index)
    this._index = index
    return text
  enddef

  # False reports that there is no following candidate; the caller handles it.
  def Next(): bool
    this._CheckActive()
    if this._index + 1 >= len(this._prepared.candidates)
      return false
    endif
    this._index += 1
    return true
  enddef

  # False asks the caller to return from the first candidate to reading display.
  def Previous(): bool
    this._CheckActive()
    if this._index == 0
      return false
    endif
    this._index -= 1
    return true
  enddef

  def Commit(): string
    this._CheckActive()
    const text = this._prepared.TextAt(this._index)
    const query = this._prepared.PreferenceQuery(this._index)
    const candidate = this._prepared.candidates[this._index]
    LearnCandidate(this._preferences, query, candidate, this._prepared.IsExperimental(this._index), this._prepared.okuri == '')
    this._active = false
    return text
  enddef

  def Cancel(): string
    this._CheckActive()
    this._active = false
    return this._prepared.query.reading .. this._prepared.okuri
  enddef
endclass

# Each row keeps its own preference identity and marker when sources interleave.
def RowIdentity(is_stem: bool, candidate: dictionary.Candidate): string
  return json_encode([is_stem, candidate.text, candidate.source_reading])
enddef

class RankedRow
  const candidate: dictionary.Candidate
  const marker: string
  const tier: number
  const direct: number
  const recent: number
  const history: number
  const source: number
  const position: number
  def new(this.candidate, this.marker, this.tier, this.direct, this.recent, this.history, this.source, this.position)
  enddef
endclass

def CompareRows(left: RankedRow, right: RankedRow): number
  for pair in [[left.tier, right.tier], [left.direct, right.direct], [left.recent, right.recent], [left.history, right.history],
      [left.source, right.source], [left.position, right.position]]
    if pair[0] != pair[1]
      return pair[0] < pair[1] ? -1 : 1
    endif
  endfor
  return 0
enddef

def MergeAnnotations(candidate: dictionary.Candidate, duplicate: dictionary.Candidate): dictionary.Candidate
  const extra = filter(copy(duplicate.annotations), (_, annotation) => index(candidate.annotations, annotation) < 0)
  return empty(extra) ? candidate : dictionary.Candidate.new(candidate.text, candidate.annotations + extra,
    candidate.has_plain_source ? 1 : 0, candidate.source_reading)
enddef

def DirectRank(preferences: user_state.State, query: dictionary.Query, candidate: dictionary.Candidate): number
  const tier = preferences.GetCandidateTier(query, candidate.text)
  return tier ==# 'pinned' ? -1 : tier ==# 'demoted' ? 2147483648
    : preferences.DirectIndex(query.reading, candidate.text)
enddef

# Prepare one conversion request without committing, learning, or buffer I/O.
export def Prepare(entries: dict<dictionary.Entry>, preferences: user_state.State, reading: string,
    okuri: string = '', small_tsu_okuri_as_t: bool = true,
    database: dict_index.Database = null_object): Candidates
  const query = lookup.CreateQuery(reading, okuri, small_tsu_okuri_as_t)
  final system_candidates = copy(lookup.Lookup(entries, query, database))
  # Standard dictionaries may omit #6 even when other numeric styles exist.
  if okuri == '' && reading =~# '^[0-9]\+$'
      && index(mapnew(system_candidates, (_, candidate) => candidate.text), '#6') < 0
    system_candidates->add(dictionary.Candidate.new('#6', []))
  endif
  final ranked = preferences.Rank(query, system_candidates)
  const ordinary_texts = okuri == '' ? mapnew(ranked, (_, candidate) => candidate.text) : []
  final experimental = adjective.Lookup(entries, preferences, reading, okuri, database)
  final markers = repeat(['［adj］'], len(experimental))
  for candidate in verb.Lookup(entries, preferences, reading, okuri, database)
    const ordinary_position = index(ordinary_texts, candidate.text)
    if ordinary_position >= 0
      ranked[ordinary_position] = MergeAnnotations(ranked[ordinary_position], candidate)
      continue
    endif
    const position = index(mapnew(experimental, (_, item) => item.text), candidate.text)
    if okuri == '' && position >= 0
      experimental[position] = MergeAnnotations(experimental[position], candidate)
    elseif position >= 0 && candidate.source_reading == ''
      markers[position] = '［adj,verb］'
    else
      experimental->add(candidate)
      markers->add('［verb］')
    endif
  endfor
  if okuri == ''
    ranked->map((_, candidate) => verb.WithStandaloneAnnotations(reading, candidate))
  endif
  const prefer_direct = okuri == '' && configuration.PreferDirectOkuriNashiLearning()
  if empty(experimental)
    if prefer_direct
      # The existing rank is the tie-breaker for candidates without direct history.
      ranked->sort((left, right) => DirectRank(preferences, query, left) - DirectRank(preferences, query, right))
    endif
    return Candidates.new(query, okuri, ranked)
  endif
  const stem_query = lookup.CreateQuery(reading, '')
  final source_queries = [query, stem_query]
  const kuru_source = verb.KuruSourceReading(reading)
  if kuru_source != ''
    source_queries->add(lookup.CreateQuery(kuru_source, ''))
  endif
  const sources = database is null_object ? [entries] : database.LookupSources(source_queries)
  final source_ranks: dict<number> = {}
  final source_positions: dict<number> = {}
  const empty_preferences = user_state.State.new()
  for source_index in range(len(sources))
    const source = sources[source_index]
    var source_position = 0
    for candidate in lookup.Lookup(source, query)
      const identity = RowIdentity(false, candidate)
      if !has_key(source_ranks, identity)
        source_ranks[identity] = source_index
        source_positions[identity] = source_position
      endif
      source_position += 1
    endfor
    final eligible = adjective.Lookup(source, empty_preferences, reading, okuri, null_object)
        + verb.Lookup(source, empty_preferences, reading, okuri, null_object)
    const eligible_texts = mapnew(eligible, (_, candidate) => candidate.text)
    final ordered = filter(copy(lookup.Lookup(source, stem_query)), (_, candidate) => index(eligible_texts, candidate.text) >= 0)
    ordered->extend(filter(copy(eligible), (_, candidate) => candidate.source_reading != ''))
    for candidate in ordered
      const identity = RowIdentity(true, candidate)
      if !has_key(source_ranks, identity)
        source_ranks[identity] = source_index
        source_positions[identity] = source_position
      endif
      source_position += 1
    endfor
  endfor
  final rows: list<RankedRow> = []
  # Within one dictionary ordinary headwords precede generated stem candidates.
  for candidate in ranked + experimental
    const position = len(rows)
    const is_stem = position >= len(ranked)
    const preference_query = candidate.source_reading != ''
      ? lookup.CreateQuery(candidate.source_reading, '') : is_stem ? stem_query : query
    const tier_name = preferences.GetCandidateTier(preference_query, candidate.text)
    const tier = tier_name ==# 'pinned' ? 0 : tier_name ==# 'demoted' ? 2 : 1
    const recent_query = candidate.source_reading != '' ? stem_query : preference_query
    const recent_index = preferences.RecentIndex(recent_query, candidate.text)
    const recent = tier == 1 && recent_index >= 0 ? recent_index : 2147483647
    const learned = preferences.HistoryIndex(preference_query, candidate.text)
    const history = tier == 1 && learned >= 0 ? learned : 2147483647
    rows->add(RankedRow.new(candidate, is_stem ? markers[position - len(ranked)] : '',
      tier, prefer_direct && tier == 1 ? preferences.DirectIndex(reading, candidate.text) : 0, recent, history, get(source_ranks, RowIdentity(is_stem, candidate), len(sources)),
      get(source_positions, RowIdentity(is_stem, candidate), position)))
  endfor
  sort(rows, CompareRows)
  return Candidates.new(query, okuri, mapnew(rows, (_, row) => row.candidate),
    mapnew(rows, (_, row) => row.marker))
enddef
