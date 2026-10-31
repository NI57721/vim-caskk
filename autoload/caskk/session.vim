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

  def new(this.text, this.unhandled, this.state, this.commit_preedit = v:none,
      this.in_candidate = v:none, this.replace_preedit = v:none)
  enddef
endclass

# Connect core input stages without depending on Vim buffers or presentation.
export class Session
  const _normalizer: normalize.Normalizer
  const _composer: composer.Composer
  const _state: state_types.State
  var _prepared: conversion.Candidates = null_object
  var _selection: conversion.Selection = null_object

  def new(compiled: scheme.CompiledScheme, sticky_key: string = '')
    this._normalizer = normalize.Normalizer.new(sticky_key)
    this._composer = composer.Composer.new(compiled)
    this._state = state_types.State.new()
  enddef

  def _Apply(matched_results: list<composer.Result>): list<Result>
    final results: list<Result> = []
    for matched in matched_results
      if matched.output is null_object
        results->add(Result.new('', matched.events, this._state.GetSnapshot()))
      else
        const composed = composer.Compose(matched, this._state.in_preedit)
        const text = this._state.Apply(composed)
        results->add(Result.new(text, [], this._state.GetSnapshot()))
      endif
    endfor
    return results
  enddef

  # Input is one physical KeyToken, already named by the integration layer.
  def Feed(key: string): list<Result>
    final results: list<Result> = []
    if this.InCandidate()
      results->extend(this.Commit())
    endif
    this._prepared = null_object
    for event in this._normalizer.Feed(key)
      results->extend(this._Apply(this._composer.Feed(event)))
    endfor
    return results
  enddef

  def Commit(): list<Result>
    if this.InCandidate()
      const text = this._selection.Commit()
      this._state.Commit()
      this._normalizer.Reset()
      this._selection = null_object
      this._prepared = null_object
      return [Result.new(text, [], this._state.GetSnapshot(), true)]
    endif
    this._prepared = null_object
    final results = this._Apply(this._composer.Flush())
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
    final results = this._Apply(this._composer.Flush())
    this._normalizer.Reset()
    for result in results
      if !empty(result.unhandled)
        return results
      endif
    endfor
    if !this._state.in_preedit || this._state.reading == ''
      return results
    endif
    this._prepared = conversion.Prepare(entries, preferences, this._state.reading, this._state.okuri)
    if empty(this._prepared.candidates)
      results->add(Result.new('', [], this._state.GetSnapshot()))
      return results
    endif
    this._selection = conversion.Selection.new(this._prepared, preferences)
    results->add(Result.new(this._selection.CurrentText(), [], this._state.GetSnapshot(), false, true, true))
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
    return Result.new(text, [], this._state.GetSnapshot(), false, false, true)
  enddef

  def Pending(): list<input.Event>
    return this._composer.Pending()
  enddef

  def GetSnapshot(): state_types.Snapshot
    return this._state.GetSnapshot()
  enddef
endclass
