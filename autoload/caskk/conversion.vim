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

# Prepare one conversion request without committing, learning, or buffer I/O.
export def Prepare(entries: dict<dictionary.Entry>, preferences: user_state.State, reading: string, okuri: string = ''): Candidates
  const query = lookup.CreateQuery(reading, okuri)
  const system_candidates = lookup.Lookup(entries, query)
  const ranked = preferences.Rank(query, system_candidates)
  return Candidates.new(query, okuri, ranked)
enddef
