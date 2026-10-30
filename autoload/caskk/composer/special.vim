vim9script

import 'caskk/output_pattern.vim' as pattern_types

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
