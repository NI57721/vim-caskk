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
  const experimental_count: number
  const candidates: list<dictionary.Candidate>

  def new(this.query, this.okuri, candidates: list<dictionary.Candidate>, experimental_count: number = 0, markers: list<string> = [])
    this.markers = copy(markers)
    this.experimental_count = experimental_count
    this.candidates = copy(candidates)
  enddef

  def PreferenceQuery(index: number): dictionary.Query
    return index < this.experimental_count ? lookup.CreateQuery(this.query.reading, '') : this.query
  enddef

  def DisplayAt(index: number): string
    return this.TextAt(index) .. (index < this.experimental_count ? (empty(this.markers) ? "［adj］" : this.markers[index]) : "")
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
    return this._index < this._prepared.experimental_count
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
  const ordered = preferences.RankCandidates(lookup.CreateQuery(reading, ''), experimental)
  final ordered_markers: list<string> = []
  for candidate in ordered
    ordered_markers->add(markers[index(experimental, candidate)])
  endfor
  return Candidates.new(query, okuri, ordered + ranked, len(ordered), ordered_markers)
enddef
