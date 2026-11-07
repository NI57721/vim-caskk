vim9script
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/user_state.vim' as user_state

# Experimental stem expansion; never applies preference ranking or learning.
export def Lookup(entries: dict<dictionary.Entry>, preferences: user_state.State,
    reading: string, okuri: string, database: dict_index.Database): list<dictionary.Candidate>
  if index(['い', 'か', 'く', 'け', 'き', 'し', 'う', 'そ', 'さ', 'み', 'め', 'げ', 'が', 'す'], strcharpart(okuri, 0, 1)) < 0
    return []
  endif
  final sources = copy(lookup.Lookup(entries, lookup.CreateQuery(reading, ''), database))
  for identity in sort(preferences.RegisteredIdentities())
    const pair: list<string> = json_decode(identity)
    if pair == [reading, '']
      sources->extend(preferences.RegisteredCandidates(identity))
    endif
  endfor
  final result: list<dictionary.Candidate> = []
  for candidate in sources
    if !empty(filter(copy(candidate.annotations), (_, annotation) => annotation =~# '\(^\|[[:space:];]\)@adj\($\|[[:space:];]\)'))
        && index(mapnew(result, (_, item) => item.text), candidate.text) < 0
      result->add(candidate)
    endif
  endfor
  return result
enddef
