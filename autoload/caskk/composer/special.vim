vim9script

import 'caskk/output_pattern.vim' as pattern_types
import 'caskk/input.vim' as input
import autoload 'caskk/composer/combination.vim' as combination

# Keys are individual normalized KeyTokens; outputs are parsed in the scheme layer.
export class Rule
  const keys: list<string>
  const output: pattern_types.OutputPattern

  def new(keys: list<string>, this.output)
    if empty(keys)
      throw 'caskk: special requires at least one key'
    endif
    this.keys = copy(keys)
  enddef
endclass

# A null output means the input is pending or must be replayed.
export class MatchResult
  const replay: list<string>
  const pending: list<string>
  const output: pattern_types.OutputPattern
  # Input after a matched special, to be matched again after processing output.
  const rest: list<string> = []

  def new(this.replay, this.pending, this.output = v:none, this.rest = v:none)
  enddef
endclass

export class EventMatchResult
  const replay: list<input.Event>
  const pending: list<input.Event>
  const output: pattern_types.OutputPattern
  const events: list<input.Event> = []
  const rest: list<input.Event> = []

  def new(this.replay, this.pending, this.output = v:none, this.events = v:none,
      this.rest = v:none)
  enddef
endclass

export class CompositionResult
  const start_conversion: bool
  const reading: string
  const okuri: string

  def new(this.start_conversion, this.reading, this.okuri)
  enddef
endclass

# Match the pending prefix plus the next input token.
# Replay is processed normally before output. Pending is retained for the next call.
# Rest is reprocessed after output. A failed extension commits the longest
# complete prefix before considering normal input or another suffix special.
export def Match(rules: list<Rule>, keys: list<string>): MatchResult
  final replay: list<string> = []
  var pending = copy(keys)
  while !empty(pending)
    var exact = -1
    var longer = false
    for index in range(len(rules))
      const rule = rules[index]
      if len(rule.keys) > len(pending)
        if rule.keys[: len(pending) - 1] == pending
          longer = true
        endif
      elseif pending[: len(rule.keys) - 1] == rule.keys
          && (exact == -1 || len(rule.keys) > len(rules[exact].keys))
        exact = index
      endif
    endfor

    if longer
      return MatchResult.new(replay, pending)
    elseif exact != -1
      return MatchResult.new(replay, [], rules[exact].output, pending[len(rules[exact].keys) :])
    endif

    # Retest every suffix, retaining the longest one that can start a special.
    replay->add(remove(pending, 0))
  endwhile
  return MatchResult.new(replay, [])
enddef

# Preserve semantic input events while matching only their normalized KeyTokens.
# The caller processes replay before interpreting a matched special in its new context.
export def MatchEvents(rules: list<Rule>, events: list<input.Event>): EventMatchResult
  final keys: list<string> = []
  for event in events
    keys->add(event.key)
  endfor
  const match = Match(rules, keys)
  const replay_count = len(match.replay)
  const match_end = len(events) - len(match.rest)
  final replay: list<input.Event> = []
  final remaining: list<input.Event> = []
  final rest: list<input.Event> = []
  for index in range(len(events))
    if index < replay_count
      replay->add(events[index])
    elseif index >= match_end
      rest->add(events[index])
    else
      remaining->add(events[index])
    endif
  endfor
  if match.output isnot null_object
    return EventMatchResult.new(replay, [], match.output, remaining, rest)
  endif
  return EventMatchResult.new(replay, remaining)
enddef

# Interpret an already matched special using the current preedit context.
# Boundary placement is determined solely by the output pattern.
export def Compose(pattern: pattern_types.OutputPattern, events: list<input.Event>,
    in_preedit: bool = false): CompositionResult
  if empty(events)
    throw 'caskk: special composition requires at least one input event'
  endif
  const first_modified = events[0].modified
  var later_modified = false
  for event in events[1 :]
    if event.modified
      later_modified = true
      break
    endif
  endfor
  const okuri_input = (in_preedit || first_modified) && later_modified
  const composed = combination.Compose('', pattern, okuri_input)
  return CompositionResult.new(!in_preedit && first_modified, composed.reading, composed.okuri)
enddef
