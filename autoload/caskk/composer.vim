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
  const is_symbol: bool = false

  def new(this.events, this.output = v:none, this.is_special = v:none, this.is_symbol = v:none)
  enddef
endclass

# Resolve Modified semantics after matching, using the caller's current state.
export def Compose(result: Result, in_preedit: bool = false): composition.Result
  if result.output is null_object
    throw 'caskk: cannot compose unmatched input'
  endif
  if result.is_symbol
    if in_preedit && result.events[0].modified
      return composition.Result.new(false, '', result.output.text, true)
    endif
    return composition.Result.new(!in_preedit && result.events[0].modified,
      result.output.text, '', false)
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
  var _consonant: list<input.Event> = []

  def new(compiled: scheme.CompiledScheme)
    this._table = compiled.table
    this._rules = compiled.specials
  enddef

  def _ConsonantKey(events: list<input.Event>): string
    var matched = ''
    for key in keys(this._table.consonants)
      const tokens = scheme.ConsonantKeys(key)
      if len(tokens) != len(events)
        continue
      endif
      var equal = true
      for index in range(0, len(tokens) - 1)
        if tokens[index] !=# events[index].key
          equal = false
          break
        endif
      endfor
      if equal
        matched = key
      endif
    endfor
    return matched
  enddef

  def _SymbolKey(events: list<input.Event>): string
    var matched = ''
    for key in keys(this._table.symbols)
      const tokens = scheme.ConsonantKeys(key)
      if len(tokens) != len(events)
        continue
      endif
      var equal = true
      for index in range(0, len(tokens) - 1)
        if tokens[index] !=# events[index].key
          equal = false
          break
        endif
      endfor
      if equal
        matched = key
      endif
    endfor
    return matched
  enddef

  def _InputKeys(): list<string>
    return keys(this._table.consonants) + keys(this._table.symbols)
  enddef

  # An explicitly configured special owns its physical first key before the
  # keyboard-layout layer interprets shifted punctuation as Modified input.
  def IsSpecialStart(key: string): bool
    for rule in this._rules
      if rule.keys[0] ==# key
        return true
      endif
    endfor
    return false
  enddef

  # Let an already pending special consume the next key before the binding
  # layer interprets that key as an action such as Convert.
  def IsSpecialContinuation(key: string): bool
    if empty(this._special_pending)
      return false
    endif
    final keys: list<string> = []
    for event in this._special_pending
      keys->add(event.key)
    endfor
    keys->add(key)
    const match = special.Match(this._rules, keys)
    return empty(match.replay) && (match.output isnot null_object || !empty(match.pending))
  enddef

  def _HasConsonantPrefix(events: list<input.Event>): bool
    for key in this._InputKeys()
      const tokens = scheme.ConsonantKeys(key)
      if len(tokens) < len(events)
        continue
      endif
      var matches = true
      for index in range(0, len(events) - 1)
        if tokens[index] !=# events[index].key
          matches = false
          break
        endif
      endfor
      if matches
        return true
      endif
    endfor
    return false
  enddef

  def _LogicalConsonant(key: string, events: list<input.Event>): input.Event
    var modified = false
    for event in events
      modified = modified || event.modified
    endfor
    return input.Event.new(key, modified)
  enddef

  # If the longest consonant row cannot generate this combination's kana,
  # resolve the earliest valid consonant/combination pair and replay its tail.
  def _ReplayFirstValidPair(events: list<input.Event>, results: list<Result>): bool
    for length in range(1, len(events) - 1)
      const key = this._ConsonantKey(events[0 : length - 1])
      if key == '' || !has_key(this._table.combinations, events[length].key)
        continue
      endif
      var pattern: pattern_types.OutputPattern = null_object
      try
        pattern = kana.Generate(this._table.consonants[key],
          this._table.combinations[events[length].key])
      catch
        if v:exception =~# '^caskk: undefined kana:'
          continue
        endif
        throw v:exception
      endtry
      results->add(Result.new([this._LogicalConsonant(key, events[0 : length - 1]),
        events[length]], pattern))
      for replayed in events[length + 1 :]
        this._Replay(replayed, results)
      endfor
      return true
    endfor
    return false
  enddef

  # Normal replay must bypass special matching to avoid retrying a failed prefix.
  def _Replay(event: input.Event, results: list<Result>)
    if !empty(this._consonant)
      const extended = this._consonant + [event]
      const extended_symbol = this._SymbolKey(extended)
      if extended_symbol != '' && !this._HasLongerConsonantPrefix(extended)
        this._consonant = []
        const pattern = pattern_types.OutputPattern.new(this._table.symbols[extended_symbol], -1)
        results->add(Result.new(extended, pattern, false, true))
        return
      endif
      if this._HasConsonantPrefix(extended)
        this._consonant = extended
        return
      endif

      var matched_key = ''
      var matched_symbol = ''
      var matched_length = 0
      for length in range(1, len(this._consonant))
        const key = this._ConsonantKey(this._consonant[0 : length - 1])
        const symbol = this._SymbolKey(this._consonant[0 : length - 1])
        if key != '' || symbol != ''
          matched_key = key
          matched_symbol = symbol
          matched_length = length
        endif
      endfor
      if matched_key != '' || matched_symbol != ''
        const matched_events = this._consonant[0 : matched_length - 1]
        const buffered_events = copy(this._consonant) + [event]
        const remainder = this._consonant[matched_length : ] + [event]
        this._consonant = []
        if matched_symbol != ''
          results->add(Result.new(matched_events,
            pattern_types.OutputPattern.new(this._table.symbols[matched_symbol], -1), false, true))
          for replayed in remainder
            this._Replay(replayed, results)
          endfor
          return
        endif
        if !empty(remainder) && has_key(this._table.combinations, remainder[0].key)
          const combination_event = remainder[0]
          var pattern: pattern_types.OutputPattern = null_object
          try
            pattern = kana.Generate(this._table.consonants[matched_key],
              this._table.combinations[combination_event.key])
          catch
            const reason = v:exception
            if reason !~# '^caskk: undefined kana:'
              throw reason
            endif
            if this._ReplayFirstValidPair(buffered_events, results)
              return
            endif
            throw reason
          endtry
          results->add(Result.new([this._LogicalConsonant(matched_key, matched_events),
            combination_event], pattern))
          for replayed in remainder[1 :]
            this._Replay(replayed, results)
          endfor
          return
        endif
        for unmatched in matched_events
          results->add(Result.new([unmatched]))
        endfor
        for replayed in remainder
          this._Replay(replayed, results)
        endfor
        return
      endif

      const first = this._consonant[0]
      const remainder = this._consonant[1 :] + [event]
      this._consonant = []
      results->add(Result.new([first]))
      for replayed in remainder
        this._Replay(replayed, results)
      endfor
      return
    endif

    const symbol = this._SymbolKey([event])
    if symbol != '' && !this._HasLongerConsonantPrefix([event])
      const pattern = pattern_types.OutputPattern.new(this._table.symbols[symbol], -1)
      results->add(Result.new([event], pattern, false, true))
    elseif has_key(this._table.consonants, event.key)
      this._consonant = [event]
    elseif this._HasConsonantPrefix([event])
      this._consonant = [event]
    elseif has_key(this._table.combinations, event.key)
      const pattern = kana.Generate('', this._table.combinations[event.key])
      results->add(Result.new([event], pattern))
    else
      results->add(Result.new([event]))
    endif
  enddef

  def _HasLongerConsonantPrefix(events: list<input.Event>): bool
    for key in this._InputKeys()
      const tokens = scheme.ConsonantKeys(key)
      if len(tokens) <= len(events)
        continue
      endif
      var matches = true
      for index in range(0, len(events) - 1)
        if tokens[index] !=# events[index].key
          matches = false
          break
        endif
      endfor
      if matches
        return true
      endif
    endfor
    return false
  enddef

  def _CompletesPendingCombination(event: input.Event): bool
    if empty(this._consonant) || !empty(this._special_pending)
        || !has_key(this._table.combinations, event.key)
      return false
    endif
    return !this._HasConsonantPrefix(this._consonant + [event])
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
      if match.output isnot null_object && len(match.events) == 1
          && match.events[0].modified && this._SymbolKey(match.events) != ''
        # A Modified N/T consonant starts an okuri boundary even when its
        # unmodified spelling is also a single-key special such as `l` -> っ.
        this._Replay(match.events[0], results)
        remaining = match.rest
        continue
      endif
      if match.output isnot null_object && !empty(this._consonant)
          && len(match.events) == 1
          && has_key(this._table.combinations, match.events[0].key)
        this._Replay(match.events[0], results)
        remaining = match.rest
        continue
      endif
      if match.output is null_object
        var pending = copy(match.pending)
        if !empty(pending) && this._CompletesPendingCombination(pending[0])
          this._Replay(pending[0], results)
          pending = pending[1 :]
          remaining = pending
          continue
        endif
        this._special_pending = pending
        break
      endif

      # A successful special consumes its own keys, leaving no combination key
      # for an earlier unmatched consonant. Return that consonant first.
      if !empty(this._consonant)
        for unmatched in this._consonant
          results->add(Result.new([unmatched]))
        endfor
        this._consonant = []
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
    if !empty(this._consonant)
      for unmatched in this._consonant
        results->add(Result.new([unmatched]))
      endfor
      this._consonant = []
    endif
    return results
  enddef

  # Remove the newest pending key without resolving or replaying it.
  def Backspace(): bool
    if !empty(this._special_pending)
      remove(this._special_pending, -1)
      return true
    endif
    if !empty(this._consonant)
      remove(this._consonant, -1)
      return true
    endif
    return false
  enddef

  def Pending(): list<input.Event>
    if !empty(this._consonant)
      return copy(this._consonant) + this._special_pending
    endif
    return copy(this._special_pending)
  enddef
endclass
