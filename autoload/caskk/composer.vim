vim9script

import 'caskk/input.vim' as input
import 'caskk/combination_table.vim' as table_types
import 'caskk/output_pattern.vim' as pattern_types
import 'caskk/composition.vim' as composition
import autoload 'caskk/composer/combination.vim' as combination
import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/scheme/kana.vim' as kana

# Results retain their input events for later Modified/preedit interpretation.
# A null output returns unmatched input to the caller without assigning behavior.
export class Result
  const events: list<input.Event>
  const output: pattern_types.OutputPattern
  const is_special: bool = false

  def new(this.events, this.output = v:none, this.is_special = v:none)
  enddef
endclass

# Resolve Modified semantics after matching, using the caller's current state.
export def Compose(result: Result, in_preedit: bool = false): composition.Result
  if result.output is null_object
    throw 'caskk: cannot compose unmatched input'
  endif
  if result.is_special
    return special.Compose(result.output, result.events, in_preedit)
  endif
  return combination.ComposeEvents(result.output, result.events, in_preedit)
enddef

export class Composer
  const _table: table_types.CombinationTable
  const _rules: list<special.Rule>
  var _special_pending: list<input.Event> = []
  var _consonant: input.Event

  def new(compiled: scheme.CompiledScheme)
    this._table = compiled.table
    this._rules = compiled.specials
  enddef

  # Normal replay must bypass special matching to avoid retrying a failed prefix.
  def _Replay(event: input.Event, results: list<Result>)
    if this._consonant isnot null_object
      if has_key(this._table.combinations, event.key)
        const pattern = kana.Generate(this._table.consonants[this._consonant.key],
          this._table.combinations[event.key])
        results->add(Result.new([this._consonant, event], pattern))
        this._consonant = null_object
        return
      endif
      results->add(Result.new([this._consonant]))
      this._consonant = null_object
    endif

    if has_key(this._table.consonants, event.key)
      this._consonant = event
    elseif has_key(this._table.combinations, event.key)
      const pattern = kana.Generate('', this._table.combinations[event.key])
      results->add(Result.new([event], pattern))
    else
      results->add(Result.new([event]))
    endif
  enddef

  def _CompletesPendingCombination(event: input.Event): bool
    if this._consonant is null_object || !empty(this._special_pending)
        || !has_key(this._table.combinations, event.key)
      return false
    endif
    return true
  enddef

  def _Process(events: list<input.Event>, end_of_input: bool): list<Result>
    var remaining = events
    this._special_pending = []
    final results: list<Result> = []
    while !empty(remaining)
      const match = special.MatchEvents(this._rules, remaining, end_of_input)
      for replayed in match.replay
        this._Replay(replayed, results)
      endfor
      this._special_pending = match.pending
      if match.output is null_object
        break
      endif

      # A successful special consumes its own keys, leaving no combination key
      # for an earlier unmatched consonant. Return that consonant first.
      if this._consonant isnot null_object
        results->add(Result.new([this._consonant]))
        this._consonant = null_object
      endif
      results->add(Result.new(match.events, match.output, true))
      remaining = match.rest
    endwhile
    return results
  enddef

  # A feed may resolve several normal combinations after a failed special.
  # Results are returned in input order, before any still-pending suffix.
  def Feed(event: input.Event): list<Result>
    if this._CompletesPendingCombination(event)
      final results: list<Result> = []
      this._Replay(event, results)
      return results
    endif
    return this._Process(this._special_pending + [event], false)
  enddef

  # Explicit end of input resolves complete specials and returns unfinished keys.
  def Flush(): list<Result>
    final results = this._Process(this._special_pending, true)
    if this._consonant isnot null_object
      results->add(Result.new([this._consonant]))
      this._consonant = null_object
    endif
    return results
  enddef

  # Remove the newest pending key without resolving or replaying it.
  def Backspace(): bool
    if !empty(this._special_pending)
      remove(this._special_pending, -1)
      return true
    endif
    if this._consonant isnot null_object
      this._consonant = null_object
      return true
    endif
    return false
  enddef

  def Pending(): list<input.Event>
    if this._consonant isnot null_object
      return [this._consonant] + this._special_pending
    endif
    return copy(this._special_pending)
  enddef
endclass
