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

  def Select(index: number): string
    this._CheckActive()
    const text = this._prepared.TextAt(index)
    this._index = index
    return text
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
export def Prepare(entries: dict<dictionary.Entry>, preferences: user_state.State, reading: string, okuri: string = ''): Candidates
  const query = lookup.CreateQuery(reading, okuri)
  const system_candidates = lookup.Lookup(entries, query)
  const ranked = preferences.Rank(query, system_candidates)
  return Candidates.new(query, okuri, ranked)
enddef
