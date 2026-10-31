vim9script

import 'caskk/input.vim' as input
import 'caskk/combination_table.vim' as table_types
import 'caskk/output_pattern.vim' as pattern_types
import autoload 'caskk/composer/special.vim' as special
import autoload 'caskk/scheme/kana.vim' as kana

# Results retain their input events for later Modified/preedit interpretation.
# A null output returns unmatched input to the caller without assigning behavior.
export class Result
  const events: list<input.Event>
  const output: pattern_types.OutputPattern

  def new(this.events, this.output = v:none)
  enddef
endclass

export class Composer
  const _table: table_types.CombinationTable
  const _rules: list<special.Rule>
  var _special_pending: list<input.Event> = []
  var _consonant: input.Event

  def new(this._table, rules: list<special.Rule>)
    this._rules = copy(rules)
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
    else
      results->add(Result.new([event]))
    endif
  enddef

  # A feed may resolve several normal combinations after a failed special.
  # Results are returned in input order, before any still-pending suffix.
  def Feed(event: input.Event): list<Result>
    var remaining = this._special_pending + [event]
    this._special_pending = []
    final results: list<Result> = []
    while !empty(remaining)
      const match = special.MatchEvents(this._rules, remaining)
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
      results->add(Result.new(match.events, match.output))
      remaining = match.rest
    endwhile
    return results
  enddef

  def Pending(): list<input.Event>
    if this._consonant isnot null_object
      return [this._consonant] + this._special_pending
    endif
    return copy(this._special_pending)
  enddef
endclass
