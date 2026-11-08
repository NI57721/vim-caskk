vim9script
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/dictionary/stem.vim' as stem

import 'caskk/verb_tags.vim' as tags

export def Lookup(entries: dict<dictionary.Entry>, preferences: user_state.State, reading: string, okuri: string, database: dict_index.Database): list<dictionary.Candidate>
  if okuri == ''
    return []
  endif
  final result: list<dictionary.Candidate> = []
  for candidate in stem.Lookup(entries, preferences, reading, database)
    var matched = false
    for annotation in candidate.annotations
      for tag in split(annotation, '[[:space:];]\+')
        if has_key(tags.ENDINGS, tag) && stridx(tags.ENDINGS[tag], strcharpart(okuri, 0, 1)) >= 0
          matched = true
        endif
      endfor
    endfor
    if matched
      result->add(candidate)
    endif
  endfor
  return result
enddef
