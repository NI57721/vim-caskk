vim9script

import 'caskk/input.vim' as input
import autoload 'caskk/input/normalize.vim' as normalize
import autoload 'caskk/composer.vim' as composer
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/state.vim' as state_types

# One ordered output and the state immediately after it.
# Text is Direct output; preedit text is retained in the state snapshot.
# Unhandled semantic events are returned without assigning buffer behavior.
export class Result
  const text: string
  const unhandled: list<input.Event>
  const state: state_types.Snapshot

  def new(this.text, this.unhandled, this.state)
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

  # Input is one physical KeyToken, already named by the integration layer.
  def Feed(key: string): list<Result>
    final results: list<Result> = []
    for event in this._normalizer.Feed(key)
      for matched in this._composer.Feed(event)
        if matched.output is null_object
          results->add(Result.new('', matched.events, this._state.GetSnapshot()))
        else
          const composed = composer.Compose(matched, this._state.in_preedit)
          const text = this._state.Apply(composed)
          results->add(Result.new(text, [], this._state.GetSnapshot()))
        endif
      endfor
    endfor
    return results
  enddef

  def Pending(): list<input.Event>
    return this._composer.Pending()
  enddef

  def GetSnapshot(): state_types.Snapshot
    return this._state.GetSnapshot()
  enddef
endclass
