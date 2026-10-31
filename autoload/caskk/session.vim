vim9script

import 'caskk/input.vim' as input
import autoload 'caskk/input/normalize.vim' as normalize
import autoload 'caskk/composer.vim' as composer
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/state.vim' as state_types

# One ordered output and the state immediately after it.
# Text is Direct output, or the reading committed by an explicit commit result.
# A commit result confirms existing preedit text rather than inserting it again.
# Unhandled semantic events are returned without assigning buffer behavior.
export class Result
  const text: string
  const unhandled: list<input.Event>
  const state: state_types.Snapshot
  const commit_preedit: bool = false

  def new(this.text, this.unhandled, this.state, this.commit_preedit = v:none)
  enddef
endclass

# Connect core input stages without depending on Vim buffers or presentation.
export class Session
  const _normalizer: normalize.Normalizer
  const _composer: composer.Composer
  const _state: state_types.State

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
    for event in this._normalizer.Feed(key)
      results->extend(this._Apply(this._composer.Feed(event)))
    endfor
    return results
  enddef

  def Commit(): list<Result>
    final results = this._Apply(this._composer.Flush())
    this._normalizer.Reset()
    if this._state.in_preedit
      const text = this._state.Commit()
      results->add(Result.new(text, [], this._state.GetSnapshot(), true))
    endif
    return results
  enddef

  def Pending(): list<input.Event>
    return this._composer.Pending()
  enddef

  def GetSnapshot(): state_types.Snapshot
    return this._state.GetSnapshot()
  enddef
endclass
