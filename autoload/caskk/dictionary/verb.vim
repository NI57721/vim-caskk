vim9script
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/dictionary/stem.vim' as stem

import 'caskk/verb_tags.vim' as tags

const STANDALONE_FORMS: dict<string> = {
  '@verb-henkaku-s': 'す$',
  '@verb-henkaku-z': 'ず$',
  '@verb-bungo-henkaku-k': '[こく]$',
  '@verb-bungo-henkaku-s': 'す$',
  '@verb-bungo-henkaku-z': 'ず$',
  '@verb-bungo-henkaku-n': '[ぬね]$',
  '@verb-bungo-henkaku-r': '[りれ]$',
}
const SEPARATOR = '[[:space:];]'

# Regular ichidan and kureru stems can stand alone; uru cannot. Other tags need a complete form,
# such as classical 来(こ) / 来(く).
def IsStandaloneTag(reading: string, tag: string): bool
  return tag ==# '@verb-1' || tag ==# '@verb-1-kureru'
    || (has_key(STANDALONE_FORMS, tag) && reading =~# STANDALONE_FORMS[tag])
enddef

export def IsStandalone(reading: string, candidate: dictionary.Candidate): bool
  for tag in split(join(candidate.annotations, ';'), SEPARATOR .. '\+')
    if IsStandaloneTag(reading, tag)
      return true
    endif
  endfor
  return false
enddef

export def WithStandaloneAnnotations(reading: string, candidate: dictionary.Candidate): dictionary.Candidate
  final annotations: list<string> = []
  for annotation in candidate.annotations
    const rejected = filter(split(annotation, SEPARATOR .. '\+'),
      (_, tag) => has_key(tags.ENDINGS, tag) && !IsStandaloneTag(reading, tag))
    const filtered = tags.WithoutTags(annotation, rejected)
    if filtered != '' || empty(rejected)
      annotations->add(filtered)
    endif
  endfor
  return annotations ==# candidate.annotations ? candidate
    : dictionary.Candidate.new(candidate.text, annotations, candidate.has_plain_source ? 1 : 0, candidate.source_reading)
enddef

# Reverse only the final reading alternation of a registered modern kuru stem.
export def KuruSourceReading(reading: string): string
  return reading =~# '[こき]$' ? strcharpart(reading, 0, strchars(reading) - 1) .. 'く' : ''
enddef

def TagAllowsOkuri(tag: string, okuri: string): bool
  return okuri !=# '' && has_key(tags.ENDINGS, tag)
    && stridx(tags.ENDINGS[tag], strcharpart(okuri, 0, 1)) >= 0
enddef

export def AllowsOkuri(candidate: dictionary.Candidate, okuri: string): bool
  return !empty(filter(split(join(candidate.annotations, ';'), SEPARATOR .. '\+'),
    (_, tag) => TagAllowsOkuri(tag, okuri)))
enddef

export def MatchedTags(candidate: dictionary.Candidate, reading: string, okuri: string): list<string>
  if candidate.source_reading !=# ''
    return ['@verb-henkaku-k']
  endif
  return filter(split(join(candidate.annotations, ';'), SEPARATOR .. '\+'),
    (_, tag) => okuri ==# '' ? IsStandaloneTag(reading, tag) : TagAllowsOkuri(tag, okuri))
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
    if AllowsOkuri(candidate, okuri)
      result->add(candidate)
    endif
  endfor
  const source_reading = KuruSourceReading(reading)
  if okuri != '' && source_reading != ''
      && stridx(tags.ENDINGS['@verb-henkaku-k'], strcharpart(okuri, 0, 1)) >= 0
    for candidate in stem.Lookup(entries, preferences, source_reading, database)
      if index(split(join(candidate.annotations, ';'), '[[:space:];]\+'), '@verb-henkaku-k') >= 0
        result->add(dictionary.Candidate.new(candidate.text, candidate.annotations, 0, source_reading))
      endif
    endfor
  endif
  return result
enddef
