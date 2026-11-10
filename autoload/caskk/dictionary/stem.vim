vim9script
import 'caskk/dictionary.vim' as dictionary
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
