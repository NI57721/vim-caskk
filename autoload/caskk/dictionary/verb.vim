vim9script
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/dictionary/stem.vim' as stem

import 'caskk/verb_tags.vim' as tags

# Regular ichidan and kureru stems can stand alone; uru cannot. Other tags need a complete form,
# such as classical 来(こ) / 来(く).
export def IsStandalone(reading: string, candidate: dictionary.Candidate): bool
  const forms: dict<string> = {
    '@verb-henkaku-s': 'す$',
    '@verb-henkaku-z': 'ず$',
    '@verb-bungo-henkaku-k': '[こく]$',
    '@verb-bungo-henkaku-s': 'す$',
    '@verb-bungo-henkaku-z': 'ず$',
    '@verb-bungo-henkaku-n': '[ぬね]$',
    '@verb-bungo-henkaku-r': '[りれ]$',
  }
  for annotation in candidate.annotations
    for tag in split(annotation, '[[:space:];]\+')
      if index(['@verb-1', '@verb-1-kureru'], tag) >= 0
        return true
      endif
      if has_key(forms, tag) && reading =~# forms[tag]
        return true
      endif
    endfor
  endfor
  return false
enddef

export def Lookup(entries: dict<dictionary.Entry>, preferences: user_state.State, reading: string, okuri: string, database: dict_index.Database): list<dictionary.Candidate>
  final result: list<dictionary.Candidate> = []
  for candidate in stem.Lookup(entries, preferences, reading, database)
    if okuri == ''
      if IsStandalone(reading, candidate)
        result->add(candidate)
      endif
      continue
    endif
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
