vim9script

import 'caskk/dictionary.vim' as dictionary

# Parse one already decoded line, without a line terminator.
# Blank/comment lines return null; invalid entries fail rather than losing data.
# Source format: https://github.com/skk-dev/dict/blob/master/committers.md
export def ParseLine(line: string): dictionary.Entry
  if stridx(line, "\n") != -1 || stridx(line, "\r") != -1
    throw 'caskk: invalid SKK dictionary entry'
  endif
  if line =~ '^\s*$' || line =~ '^\s*;;'
    return null_object
  endif

  const fields: list<string> = matchlist(line, '^\([^[:space:]]\+\)[ \t]\+\(/.*\/\)$')
  if empty(fields)
    throw 'caskk: invalid SKK dictionary entry'
  endif
  const contents = strpart(fields[2], 1, strlen(fields[2]) - 2)
  if contents == ''
    throw 'caskk: invalid SKK dictionary entry'
  endif

  final candidates: list<dictionary.Candidate> = []
  for token in split(contents, '/', true)
    const separator = stridx(token, ';')
    const text = separator == -1 ? token : strpart(token, 0, separator)
    if text == ''
      throw 'caskk: invalid SKK dictionary entry'
    endif
    # These are personal-dictionary structures, not ordinary system candidates.
    if stridx(text, '[') == 0 || text == ']'
      throw 'caskk: unsupported SKK okuri block'
    endif

    final annotations: list<string> = []
    if separator != -1
      const annotation = strpart(token, separator + 1)
      if annotation != ''
        annotations->add(annotation)
      endif
    endif
    # Lisp/concat notation is retained verbatim; this layer only splits fields.
    candidates->add(dictionary.Candidate.new(text, annotations))
  endfor
  return dictionary.Entry.new(fields[1], candidates)
enddef
