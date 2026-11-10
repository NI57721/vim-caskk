vim9script
import 'caskk/dictionary.vim' as dictionary
import 'caskk/verb_tags.vim' as tags
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/user_state.vim' as user_state

export def Lookup(entries: dict<dictionary.Entry>, preferences: user_state.State, reading: string, database: dict_index.Database): list<dictionary.Candidate>
  final sources = copy(lookup.Lookup(entries, lookup.CreateQuery(reading, ''), database))
  for identity in sort(preferences.RegisteredIdentities())
    const pair: list<string> = json_decode(identity)
    # User registration retains exact okuri; tagged stems apply across endings.
    if pair[0] ==# reading
      sources->extend(preferences.RegisteredCandidates(identity))
    endif
  endfor
  return sources
enddef


# A generated candidate may come from user registrations with any exact okuri.
# Keep ordinary registrations of the same spelling independent.
export def RegisteredQueries(preferences: user_state.State, reading: string,
    text: string): list<dictionary.Query>
  final result: list<dictionary.Query> = []
  for identity in sort(preferences.RegisteredIdentities())
    const pair: list<string> = json_decode(identity)
    if pair[0] !=# reading
      continue
    endif
    for candidate in preferences.RegisteredCandidates(identity)
      if candidate.text ==# text && (tags.HasVerb(candidate.annotations)
          || !empty(filter(copy(candidate.annotations), (_, annotation) =>
            annotation =~# '\(^\|[[:space:];]\)@adj\($\|[[:space:];]\)')))
        result->add(lookup.CreateQuery(pair[0], pair[1]))
        break
      endif
    endfor
  endfor
  return result
enddef
