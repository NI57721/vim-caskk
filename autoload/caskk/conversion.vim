vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/numeric.vim' as numeric
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/user_state.vim' as user_state

import autoload 'caskk/dictionary/verb.vim' as verb
import autoload 'caskk/dictionary/adjective.vim' as adjective

# Candidate text stays separate from the full okuri used for presentation.
export class Candidates
  const query: dictionary.Query
  const okuri: string
  const markers: list<string>
  const experimental_flags: list<bool>
  const experimental_count: number
  const candidates: list<dictionary.Candidate>

  def new(this.query, this.okuri, candidates: list<dictionary.Candidate>, experimental_count: number = 0, markers: list<string> = [], experimental_flags: list<bool> = [])
    this.experimental_flags = copy(experimental_flags)
    this.markers = copy(markers)
    this.experimental_count = experimental_count
    this.candidates = copy(candidates)
  enddef

  def PreferenceQuery(index: number): dictionary.Query
    return this.IsExperimental(index) ? lookup.CreateQuery(this.query.reading, '') : this.query
  enddef

  def IsExperimental(index: number): bool
    return empty(this.experimental_flags) ? index < this.experimental_count : this.experimental_flags[index]
  enddef

  def DisplayAt(index: number): string
    return this.TextAt(index) .. (this.IsExperimental(index) ? (empty(this.markers) ? "［adj］" : this.markers[index]) : "")
  enddef

  def TextAt(index: number): string
    if index < 0 || index >= len(this.candidates)
      throw 'caskk: conversion candidate index out of range: ' .. index
    endif
    return numeric.ExpandPlaceholders(this.candidates[index].text, this.query.reading) .. this.okuri
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

# One selection lifecycle. Buffer changes and returning to Preedit are handled
# by the caller; Cancel returns the original reading text to display there.
export class Selection
  const _prepared: Candidates
  const _preferences: user_state.State
  var _index: number = 0
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

  def CurrentText(): string
    this._CheckActive()
    return this._prepared.TextAt(this._index)
  enddef

  def GetInfo(): CandidateInfo
    this._CheckActive()
    const candidate = this._prepared.candidates[this._index]
    return CandidateInfo.new(this._index, len(this._prepared.candidates),
      this._prepared.DisplayAt(this._index), candidate.annotations,
      this._preferences.GetCandidateTier(this._prepared.PreferenceQuery(this._index), candidate.text))
  enddef

  def CurrentCandidateText(): string
    this._CheckActive()
    return this._prepared.candidates[this._index].text
  enddef

  def GetCandidatesInfo(): CandidateListInfo
    this._CheckActive()
    final candidates: list<CandidateInfo> = []
    const count = len(this._prepared.candidates)
    for index in range(0, count - 1)
      const candidate = this._prepared.candidates[index]
      candidates->add(CandidateInfo.new(index, count, this._prepared.DisplayAt(index), candidate.annotations,
        this._preferences.GetCandidateTier(this._prepared.PreferenceQuery(index), candidate.text)))
    endfor
    return CandidateListInfo.new(this._index, candidates)
  enddef

  def IsExperimental(): bool
    return this._prepared.IsExperimental(this._index)
  enddef

  def TogglePin(): string
    this._CheckActive()
    const text = this._prepared.candidates[this._index].text
    return this._preferences.TogglePin(this._prepared.PreferenceQuery(this._index), text)
  enddef

  def ToggleDemote(): string
    this._CheckActive()
    const text = this._prepared.candidates[this._index].text
    return this._preferences.ToggleDemote(this._prepared.PreferenceQuery(this._index), text)
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
    this._preferences.Learn(this._prepared.PreferenceQuery(this._index), this._prepared.candidates[this._index].text)
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
class RankedRow
  const candidate: dictionary.Candidate
  const marker: string
  const tier: number
  const recent: number
  const history: number
  const source: number
  const position: number
  def new(this.candidate, this.marker, this.tier, this.recent, this.history, this.source, this.position)
  enddef
endclass

def CompareRows(left: RankedRow, right: RankedRow): number
  for pair in [[left.tier, right.tier], [left.recent, right.recent], [left.history, right.history],
      [left.source, right.source], [left.position, right.position]]
    if pair[0] != pair[1]
      return pair[0] < pair[1] ? -1 : 1
    endif
  endfor
  return 0
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
  const ranked = preferences.Rank(query, system_candidates)
  final experimental = adjective.Lookup(entries, preferences, reading, okuri, database)
  final markers = repeat(['［adj］'], len(experimental))
  for candidate in verb.Lookup(entries, preferences, reading, okuri, database)
    const position = index(mapnew(experimental, (_, item) => item.text), candidate.text)
    if position >= 0
      markers[position] = '［adj,verb］'
    else
      experimental->add(candidate)
      markers->add('［verb］')
    endif
  endfor
  if empty(experimental)
    return Candidates.new(query, okuri, ranked)
  endif
  const stem_query = lookup.CreateQuery(reading, '')
  const sources = database is null_object ? [entries] : database.LookupSources([query, stem_query])
  final source_ranks: dict<number> = {}
  final source_positions: dict<number> = {}
  const empty_preferences = user_state.State.new()
  for source_index in range(len(sources))
    const source = sources[source_index]
    var source_position = 0
    for candidate in lookup.Lookup(source, query)
      const identity = json_encode([false, candidate.text])
      if !has_key(source_ranks, identity)
        source_ranks[identity] = source_index
        source_positions[identity] = source_position
      endif
      source_position += 1
    endfor
    const eligible = adjective.Lookup(source, empty_preferences, reading, okuri, null_object)
        + verb.Lookup(source, empty_preferences, reading, okuri, null_object)
    const eligible_texts = mapnew(eligible, (_, candidate) => candidate.text)
    for candidate in lookup.Lookup(source, stem_query)
      if index(eligible_texts, candidate.text) < 0
        continue
      endif
      const identity = json_encode([true, candidate.text])
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
    const preference_query = is_stem ? stem_query : query
    const tier_name = preferences.GetCandidateTier(preference_query, candidate.text)
    const tier = tier_name ==# 'pinned' ? 0 : tier_name ==# 'demoted' ? 2 : 1
    const recent_index = preferences.RecentIndex(preference_query, candidate.text)
    const recent = tier == 1 && recent_index >= 0 ? recent_index : 2147483647
    const learned = preferences.HistoryIndex(preference_query, candidate.text)
    const history = tier == 1 && learned >= 0 ? learned : 2147483647
    rows->add(RankedRow.new(candidate, is_stem ? markers[position - len(ranked)] : '',
      tier, recent, history, get(source_ranks, json_encode([is_stem, candidate.text]), len(sources)),
      get(source_positions, json_encode([is_stem, candidate.text]), position)))
  endfor
  sort(rows, CompareRows)
  return Candidates.new(query, okuri, mapnew(rows, (_, row) => row.candidate), len(experimental),
    mapnew(rows, (_, row) => row.marker), mapnew(rows, (_, row) => row.marker != ''))
enddef
