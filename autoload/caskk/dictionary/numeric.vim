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
def NumberRuns(reading: string): list<string>
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
  return numbers
enddef

const KANJI_DIGITS = ['〇', '一', '二', '三', '四', '五', '六', '七', '八', '九']
const DAIJI_DIGITS = ['零', '壱', '弐', '参', '四', '伍', '六', '七', '八', '九']
const POSITION_UNITS = ['', '十', '百', '千']
const DAIJI_POSITION_UNITS = ['', '拾', '百', '阡']
const LARGE_UNITS = ['', '万', '億', '兆', '京', '垓', '秭', '穣', '溝', '澗', '正', '載', '極',
  '恒河沙', '阿僧祇', '那由他', '不可思議', '無量大数']
const DAIJI_LARGE_UNITS = ['', '萬', '億', '兆', '京', '垓', '秭', '穣', '溝', '澗', '正', '載', '極',
  '恒河沙', '阿僧祇', '那由他', '不可思議', '無量大数']

def DigitByDigit(number: string, daiji: bool = false): string
  var output = ''
  const digits = daiji ? DAIJI_DIGITS : KANJI_DIGITS
  for index in range(strchars(number))
    output ..= digits[str2nr(strcharpart(number, index, 1))]
  endfor
  return output
enddef

def PositionalKanji(number: string, daiji: bool): string
  var normalized = substitute(number, '^0\+', '', '')
  if normalized ==# ''
    return daiji ? '零' : '〇'
  endif
  const digits = daiji ? DAIJI_DIGITS : KANJI_DIGITS
  const original = normalized
  const position_units = daiji ? DAIJI_POSITION_UNITS : POSITION_UNITS
  const large_units = daiji ? DAIJI_LARGE_UNITS : LARGE_UNITS
  var output = ''
  var group_index = 0
  while normalized !=# ''
    const group_length = min([4, strchars(normalized)])
    const group = strcharpart(normalized, strchars(normalized) - group_length, group_length)
    normalized = strcharpart(normalized, 0, strchars(normalized) - group_length)
    var rendered_group = ''
    for index in range(strchars(group))
      const place = strchars(group) - index - 1
      const digit = str2nr(strcharpart(group, index, 1))
      if digit == 0
        continue
      endif
      if digit != 1 || place == 0 || daiji
        rendered_group ..= digits[digit]
      endif
      rendered_group ..= position_units[place]
    endfor
    if rendered_group !=# ''
      if group_index >= len(large_units)
        return DigitByDigit(original, daiji)
      endif
      output = rendered_group .. large_units[group_index] .. output
    endif
    group_index += 1
  endwhile
  return output
enddef

def GroupThousands(number: string): string
  var output = ''
  for index in range(strchars(number))
    if index > 0 && (strchars(number) - index) % 3 == 0
      output ..= ','
    endif
    output ..= strcharpart(number, index, 1)
  endfor
  return output
enddef

def RomanNumeral(number: string): string
  var value = str2nr(number)
  if value == 0
    return 'N'
  endif
  if value > 3999
    # Additive M notation remains unambiguous for larger ordinary integers.
    var thousands = value / 1000
    var output = repeat('M', thousands)
    value %= 1000
    for [amount, symbol] in [[900, 'CM'], [500, 'D'], [400, 'CD'], [100, 'C'],
        [90, 'XC'], [50, 'L'], [40, 'XL'], [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I']]
      while value >= amount
        output ..= symbol
        value -= amount
      endwhile
    endfor
    return output
  endif
  var output = ''
  for [amount, symbol] in [[1000, 'M'], [900, 'CM'], [500, 'D'], [400, 'CD'], [100, 'C'],
      [90, 'XC'], [50, 'L'], [40, 'XL'], [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I']]
    while value >= amount
      output ..= symbol
      value -= amount
    endwhile
  endfor
  return output
enddef

def ConvertNumber(number: string, kind: string): string
  if kind ==# '0'
    return number
  elseif kind ==# '1'
    var output = ''
    for index in range(strchars(number))
      output ..= nr2char(char2nr(strcharpart(number, index, 1)) + 0xfee0, true)
    endfor
    return output
  elseif kind ==# '2'
    return DigitByDigit(number)
  elseif kind ==# '3'
    return PositionalKanji(number, false)
  elseif kind ==# '5'
    return PositionalKanji(number, true)
  elseif kind ==# '6'
    return RomanNumeral(number)
  elseif kind ==# '8'
    return GroupThousands(number)
  endif
  return '#' .. kind
enddef

# Expand supported DDSKK numeric types with corresponding input digit runs.
export def ExpandPlaceholders(candidate: string, reading: string): string
  const numbers = NumberRuns(reading)

  var expanded = ''
  var number_index = 0
  var index = 0
  while index < strchars(candidate)
    const character = strcharpart(candidate, index, 1)
    if character ==# '#' && index + 1 < strchars(candidate)
        && strcharpart(candidate, index + 1, 1) =~# '^[0-9]$'
        && number_index < len(numbers)
      const kind = strcharpart(candidate, index + 1, 1)
      expanded ..= ConvertNumber(numbers[number_index], kind)
      number_index += 1
      index += 2
    else
      expanded ..= character
      index += 1
    endif
  endwhile
  return expanded
enddef

export def ExpandZeroPlaceholders(candidate: string, reading: string): string
  return ExpandPlaceholders(candidate, reading)
enddef
