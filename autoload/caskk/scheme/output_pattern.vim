vim9script

import 'caskk/output_pattern.vim' as pattern_types

const BACKSLASH = char2nr('\')
const STAR = char2nr('*')

# Only \* and \\ are escapes; other backslashes are preserved literally.
export def Parse(pattern: string): pattern_types.OutputPattern
  final output: list<number> = []
  var boundary = -1
  var escaped = false

  for character in str2list(pattern, true)
    if escaped
      escaped = false
      if character == STAR || character == BACKSLASH
        output->add(character)
        continue
      endif
      output->add(BACKSLASH)
    endif

    if character == BACKSLASH
      escaped = true
    elseif character == STAR
      if boundary != -1
        throw 'caskk: output pattern contains multiple latent okuri boundaries'
      endif
      boundary = len(output)
    else
      output->add(character)
    endif
  endfor

  if escaped
    output->add(BACKSLASH)
  endif

  return pattern_types.OutputPattern.new(list2str(output, true), boundary)
enddef
