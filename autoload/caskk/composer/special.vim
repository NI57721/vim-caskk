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

# Match the pending prefix plus the next input token.
# Replay is processed normally before output. Pending is retained for the next call.
# An output field is present only when an unambiguous special has matched.
export def Match(rules: list<Rule>, keys: list<string>): dict<any>
  final replay: list<string> = []
  var pending = copy(keys)
  while !empty(pending)
    var exact = -1
    var longer = false
    for index in range(len(rules))
      const rule = rules[index]
      if len(rule.keys) < len(pending) || rule.keys[: len(pending) - 1] != pending
        continue
      endif
      if len(rule.keys) == len(pending)
        exact = index
      else
        longer = true
      endif
    endfor

    if longer
      return {replay: replay, pending: pending}
    elseif exact != -1
      return {replay: replay, pending: [], output: rules[exact].output}
    endif

    # Retest every suffix, retaining the longest one that can start a special.
    replay->add(remove(pending, 0))
  endwhile
  return {replay: replay, pending: []}
enddef

# Preserve semantic input events while matching only their normalized KeyTokens.
# The caller processes replay before interpreting a matched special in its new context.
export def MatchEvents(rules: list<Rule>, events: list<input.Event>): dict<any>
  final keys: list<string> = []
  for event in events
    keys->add(event.key)
  endfor
  const match = Match(rules, keys)
  const replay_count = len(match.replay)
  final replay: list<input.Event> = []
  final remaining: list<input.Event> = []
  for index in range(len(events))
    if index < replay_count
      replay->add(events[index])
    else
      remaining->add(events[index])
    endif
  endfor
  if has_key(match, 'output')
    return {replay: replay, pending: [], output: match.output, events: remaining}
  endif
  return {replay: replay, pending: remaining}
enddef

# Interpret an already matched special using the current preedit context.
# Boundary placement is determined solely by the output pattern.
export def Compose(pattern: pattern_types.OutputPattern, events: list<input.Event>,
    in_preedit: bool = false): dict<any>
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
  return {
    start_conversion: !in_preedit && first_modified,
    reading: composed.reading,
    okuri: composed.okuri,
  }
enddef
