vim9script

def IsAsciiDigit(character: string): bool
  const code = char2nr(character)
  return code >= 0x30 && code <= 0x39
enddef

# SKK numeric dictionary keys replace each contiguous ASCII digit run with #.
export def NormalizeLookupReading(reading: string): string
  var normalized = ''
  var index = 0
  var in_digits = false
  while index < strchars(reading)
    const character = strcharpart(reading, index, 1)
    if IsAsciiDigit(character)
      if !in_digits
        normalized ..= '#'
      endif
      in_digits = true
    else
      normalized ..= character
      in_digits = false
    endif
    index += 1
  endwhile
  return normalized
enddef

# Expand #0 placeholders in candidate text with corresponding input digit runs.
export def ExpandZeroPlaceholders(candidate: string, reading: string): string
  final numbers: list<string> = []
  var index = 0
  while index < strchars(reading)
    const character = strcharpart(reading, index, 1)
    if !IsAsciiDigit(character)
      index += 1
      continue
    endif
    var number = ''
    while index < strchars(reading)
      const digit = strcharpart(reading, index, 1)
      if !IsAsciiDigit(digit)
        break
      endif
      number ..= digit
      index += 1
    endwhile
    numbers->add(number)
  endwhile

  var expanded = ''
  var number_index = 0
  index = 0
  while index < strchars(candidate)
    const character = strcharpart(candidate, index, 1)
    if character ==# '#' && index + 1 < strchars(candidate)
        && strcharpart(candidate, index + 1, 1) ==# '0' && number_index < len(numbers)
      expanded ..= numbers[number_index]
      number_index += 1
      index += 2
    else
      expanded ..= character
      index += 1
    endif
  endwhile
  return expanded
enddef
