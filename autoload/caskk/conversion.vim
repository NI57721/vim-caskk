vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state

# Candidate text stays separate from the full okuri used for presentation.
export class Candidates
  const query: dictionary.Query
  const okuri: string
  const candidates: list<dictionary.Candidate>

  def new(this.query, this.okuri, candidates: list<dictionary.Candidate>)
    this.candidates = copy(candidates)
  enddef

  def TextAt(index: number): string
    if index < 0 || index >= len(this.candidates)
      throw 'caskk: conversion candidate index out of range: ' .. index
    endif
    return this.candidates[index].text .. this.okuri
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
      this._prepared.TextAt(this._index), candidate.annotations,
      this._preferences.GetCandidateTier(this._prepared.query, candidate.text))
  enddef

  def GetCandidatesInfo(): CandidateListInfo
    this._CheckActive()
    final candidates: list<CandidateInfo> = []
    const count = len(this._prepared.candidates)
    for index in range(0, count - 1)
      const candidate = this._prepared.candidates[index]
      candidates->add(CandidateInfo.new(index, count, this._prepared.TextAt(index), candidate.annotations,
        this._preferences.GetCandidateTier(this._prepared.query, candidate.text)))
    endfor
    return CandidateListInfo.new(this._index, candidates)
  enddef

  def TogglePin(): string
    this._CheckActive()
    const text = this._prepared.candidates[this._index].text
    return this._preferences.TogglePin(this._prepared.query, text)
  enddef

  def ToggleDemote(): string
    this._CheckActive()
    const text = this._prepared.candidates[this._index].text
    return this._preferences.ToggleDemote(this._prepared.query, text)
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
    const text = this.CurrentText()
    this._preferences.Learn(this._prepared.query, this._prepared.candidates[this._index].text)
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
    okuri: string = '', small_tsu_okuri_as_t: bool = true): Candidates
  const query = lookup.CreateQuery(reading, okuri, small_tsu_okuri_as_t)
  const system_candidates = lookup.Lookup(entries, query)
  const ranked = preferences.Rank(query, system_candidates)
  return Candidates.new(query, okuri, ranked)
enddef
