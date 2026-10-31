vim9script

import 'caskk/input.vim' as input
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/input/normalize.vim' as normalize
import autoload 'caskk/composer.vim' as composer
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/state.vim' as state_types

# One ordered output and the state immediately after it.
# Text is Direct output, committed text, or replacement text for Preedit.
# A commit result confirms existing preedit text rather than inserting it again.
# replace_preedit replaces that range while keeping the composition open.
# The state snapshot retains the original reading even during candidate display.
# Unhandled semantic events are returned without assigning buffer behavior.
export class Result
  const text: string
  const unhandled: list<input.Event>
  const state: state_types.Snapshot
  const commit_preedit: bool = false
  const in_candidate: bool = false
  const replace_preedit: bool = false
  const registration_requested: bool = false

  def new(this.text, this.unhandled, this.state, this.commit_preedit = v:none,
      this.in_candidate = v:none, this.replace_preedit = v:none,
      this.registration_requested = v:none)
  enddef
endclass

# Connect core input stages without depending on Vim buffers or presentation.
export class Session
  const _normalizer: normalize.Normalizer
  const _composer: composer.Composer
  const _state: state_types.State
  const _entries: dict<dictionary.Entry>
  const _preferences: user_state.State
  var _prepared: conversion.Candidates = null_object
  var _selection: conversion.Selection = null_object
  var _reading_after_cancel: bool = false

  def new(compiled: scheme.CompiledScheme, sticky_key: string = '',
      entries: dict<dictionary.Entry> = {}, preferences: user_state.State = null_object)
    this._normalizer = normalize.Normalizer.new(sticky_key)
    this._composer = composer.Composer.new(compiled)
    this._state = state_types.State.new()
    this._entries = copy(entries)
    this._preferences = preferences is null_object ? user_state.State.new() : preferences
  enddef

  def _PrepareConversion(entries: dict<dictionary.Entry>, preferences: user_state.State): Result
    this._reading_after_cancel = false
    this._prepared = conversion.Prepare(entries, preferences, this._state.reading, this._state.okuri)
    if empty(this._prepared.candidates)
      return Result.new('', [], this._state.GetSnapshot(), false, false, false, true)
    endif
    this._selection = conversion.Selection.new(this._prepared, preferences)
    return Result.new(this._selection.CurrentText(), [], this._state.GetSnapshot(), false, true, true)
  enddef

  def _Apply(matched_results: list<composer.Result>, auto_convert: bool = true): list<Result>
    final results: list<Result> = []
    for matched in matched_results
      if this.InCandidate()
        results->extend(this.Commit())
      endif
      if matched.output is null_object
        results->add(Result.new('', matched.events, this._state.GetSnapshot()))
      else
        const composed = composer.Compose(matched, this._state.in_preedit)
        const text = this._state.Apply(composed)
        if auto_convert && this._state.in_preedit && this._state.okuri_started && this._state.okuri != ''
          results->add(this._PrepareConversion(this._entries, this._preferences))
        else
          results->add(Result.new(text, [], this._state.GetSnapshot()))
        endif
      endif
    endfor
    return results
  enddef

  # Input is one physical KeyToken, already named by the integration layer.
  def Feed(key: string): list<Result>
    final results: list<Result> = []
    if this.InCandidate() || (this._reading_after_cancel && this._state.okuri != '')
      results->extend(this.Commit())
    endif
    this._prepared = null_object
    for event in this._normalizer.Feed(key)
      results->extend(this._Apply(this._composer.Feed(event)))
    endfor
    return results
  enddef

  def Commit(): list<Result>
    this._reading_after_cancel = false
    if this.InCandidate()
      const text = this._selection.Commit()
      this._state.Commit()
      this._normalizer.Reset()
      this._selection = null_object
      this._prepared = null_object
      return [Result.new(text, [], this._state.GetSnapshot(), true)]
    endif
    this._prepared = null_object
    final results = this._Apply(this._composer.Flush(), false)
    this._normalizer.Reset()
    if this._state.in_preedit
      const text = this._state.Commit()
      results->add(Result.new(text, [], this._state.GetSnapshot(), true))
    endif
    return results
  enddef

  def InCandidate(): bool
    return this._selection isnot null_object && this._selection.IsActive()
  enddef

  # A missing dictionary key leaves an empty set here for registration UI.
  # Otherwise no prepared request is represented by null_object.
  def GetCandidates(): conversion.Candidates
    return this._prepared
  enddef

  def StartConversion(entries: dict<dictionary.Entry>, preferences: user_state.State): list<Result>
    if this.InCandidate()
      throw 'caskk: conversion selection is active'
    endif
    this._prepared = null_object
    final results = this._Apply(this._composer.Flush(), false)
    this._normalizer.Reset()
    for result in results
      if !empty(result.unhandled)
        return results
      endif
    endfor
    if !this._state.in_preedit || this._state.reading == ''
      return results
    endif
    results->add(this._PrepareConversion(entries, preferences))
    return results
  enddef

  def SelectCandidate(index: number): Result
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    const text = this._selection.Select(index)
    return Result.new(text, [], this._state.GetSnapshot(), false, true, true)
  enddef

  def CancelConversion(): Result
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    const text = this._selection.Cancel()
    this._selection = null_object
    this._prepared = null_object
    this._reading_after_cancel = true
    return Result.new(text, [], this._state.GetSnapshot(), false, false, true)
  enddef

  def PreviousCandidate(): Result
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    if this._selection.Previous()
      return Result.new(this._selection.CurrentText(), [], this._state.GetSnapshot(), false, true, true)
    endif
    return this.CancelConversion()
  enddef

  def NextCandidate(): Result
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    if this._selection.Next()
      return Result.new(this._selection.CurrentText(), [], this._state.GetSnapshot(), false, true, true)
    endif
    # Exhaustion requests registration rather than committing or wrapping.
    # Keep the prepared query and full okuri for the separate registration UI.
    const text = this._selection.Cancel()
    this._selection = null_object
    this._reading_after_cancel = false
    return Result.new(text, [], this._state.GetSnapshot(), false, false, true, true)
  enddef

  def Pending(): list<input.Event>
    return this._composer.Pending()
  enddef

  def GetSnapshot(): state_types.Snapshot
    return this._state.GetSnapshot()
  enddef
endclass
