vim9script
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/user_state.vim' as user_state

import autoload 'caskk/dictionary/stem.vim' as stem

export def AllowsOkuri(candidate: dictionary.Candidate, okuri: string): bool
  return index(split('いかくけきしうそさみめげがす', '\zs'), strcharpart(okuri, 0, 1)) >= 0
    && index(split(join(candidate.annotations, ';'), '[[:space:];]\+'), '@adj') >= 0
enddef

# Experimental stem expansion; never applies preference ranking or learning.
export def Lookup(entries: dict<dictionary.Entry>, preferences: user_state.State,
    reading: string, okuri: string, database: dict_index.Database): list<dictionary.Candidate>
  if index(['い', 'か', 'く', 'け', 'き', 'し', 'う', 'そ', 'さ', 'み', 'め', 'げ', 'が', 'す'], strcharpart(okuri, 0, 1)) < 0
    return []
  endif
  const sources = stem.Lookup(entries, preferences, reading, database)
  final result: list<dictionary.Candidate> = []
  for candidate in sources
    if AllowsOkuri(candidate, okuri)
        && index(mapnew(result, (_, item) => item.text), candidate.text) < 0
      result->add(candidate)
    endif
  endfor
  return result
enddef
