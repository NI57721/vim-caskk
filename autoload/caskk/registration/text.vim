vim9script

import 'caskk/dictionary.vim' as dictionary

# Registration drafts use the first semicolon as the annotation separator.
export def Parse(text: string): dictionary.Candidate
  const separator = stridx(text, ';')
  if separator < 0
    return dictionary.Candidate.new(text, [])
  endif
  const annotation = strpart(text, separator + 1)
  return dictionary.Candidate.new(strpart(text, 0, separator),
    annotation == '' ? [] : [annotation])
enddef
