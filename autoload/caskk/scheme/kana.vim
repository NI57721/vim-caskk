vim9script

import 'caskk/output_pattern.vim' as pattern_types

export class KanaTable
  const vowels: list<string>
  const rows: dict<list<string>>
  const symbols: dict<string>

  def new(this.vowels, this.rows, this.symbols)
  enddef
endclass

# Fixed output vocabulary shared by generation and its tests.
export const TABLE: KanaTable = KanaTable.new(
  ['a', 'i', 'u', 'e', 'o'],
  {
    '': ['あ', 'い', 'う', 'え', 'お'],
    x: ['ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ'],
    xy: ['ゃ', 'ぃ', 'ゅ', 'ぇ', 'ょ'],
    xw: ['ゎ', 'ぃ', 'ぅ', 'ぇ', 'ぉ'],
    k: ['か', 'き', 'く', 'け', 'こ'],
    ky: ['きゃ', 'き', 'きゅ', 'きぇ', 'きょ'],
    g: ['が', 'ぎ', 'ぐ', 'げ', 'ご'],
    gy: ['ぎゃ', 'ぎ', 'ぎゅ', 'ぎぇ', 'ぎょ'],
    s: ['さ', 'し', 'す', 'せ', 'そ'],
    sy: ['しゃ', 'し', 'しゅ', 'しぇ', 'しょ'],
    z: ['ざ', 'じ', 'ず', 'ぜ', 'ぞ'],
    zy: ['じゃ', 'じ', 'じゅ', 'じぇ', 'じょ'],
    t: ['た', 'ち', 'つ', 'て', 'と'],
    ty: ['ちゃ', 'ち', 'ちゅ', 'ちぇ', 'ちょ'],
    ts: ['つぁ', 'つぃ', 'つ', 'つぇ', 'つぉ'],
    th: ['てゃ', 'てぃ', 'てゅ', 'てぇ', 'てょ'],
    d: ['だ', 'ぢ', 'づ', 'で', 'ど'],
    dy: ['ぢゃ', 'ぢ', 'ぢゅ', 'ぢぇ', 'ぢょ'],
    dh: ['でゃ', 'でぃ', 'でゅ', 'でぇ', 'でょ'],
    n: ['な', 'に', 'ぬ', 'ね', 'の'],
    ny: ['にゃ', 'に', 'にゅ', 'にぇ', 'にょ'],
    h: ['は', 'ひ', 'ふ', 'へ', 'ほ'],
    hy: ['ひゃ', 'ひ', 'ひゅ', 'ひぇ', 'ひょ'],
    f: ['ふぁ', 'ふぃ', 'ふ', 'ふぇ', 'ふぉ'],
    b: ['ば', 'び', 'ぶ', 'べ', 'ぼ'],
    by: ['びゃ', 'び', 'びゅ', 'びぇ', 'びょ'],
    v: ['ゔぁ', 'ゔぃ', 'ゔ', 'ゔぇ', 'ゔぉ'],
    p: ['ぱ', 'ぴ', 'ぷ', 'ぺ', 'ぽ'],
    py: ['ぴゃ', 'ぴ', 'ぴゅ', 'ぴぇ', 'ぴょ'],
    m: ['ま', 'み', 'む', 'め', 'も'],
    my: ['みゃ', 'み', 'みゅ', 'みぇ', 'みょ'],
    y: ['や', 'い', 'ゆ', 'いぇ', 'よ'],
    r: ['ら', 'り', 'る', 'れ', 'ろ'],
    ry: ['りゃ', 'り', 'りゅ', 'りぇ', 'りょ'],
    w: ['わ', 'うぃ', 'う', 'うぇ', 'を'],
    wh: ['うぁ', 'うぃ', 'う', 'うぇ', 'うぉ'],
  },
  {N: 'ん', T: 'っ'})

def GenerateCharacter(row: string, character: string): string
  const vowel = index(TABLE.vowels, character)
  if vowel != -1
    const generated = TABLE.rows[row][vowel]
    if generated == ''
      throw 'caskk: undefined kana: ' .. row .. character
    endif
    return generated
  elseif has_key(TABLE.symbols, character)
    return TABLE.symbols[character]
  elseif character =~ '[A-Za-z]'
    throw 'caskk: invalid combination symbol: ' .. character
  endif
  return character
enddef

def GenerateOkuri(text: string): string
  final output: list<string> = []
  var row = ''
  for codepoint in str2list(text, true)
    const character = nr2char(codepoint, true)
    const vowel = index(TABLE.vowels, character)
    if vowel >= 0
      if !has_key(TABLE.rows, row)
        throw 'caskk: invalid combination symbol: ' .. row
      endif
      output->add(GenerateCharacter(row, character))
      row = ''
    elseif character =~ '[a-z]'
      row ..= character
      if !has_key(TABLE.rows, row)
        throw 'caskk: invalid combination symbol: ' .. row
      endif
    elseif has_key(TABLE.symbols, character) && row == ''
      output->add(TABLE.symbols[character])
    elseif character =~ '[A-Z]' && row == ''
      output->add(GenerateCharacter('', character))
    elseif character !~ '[A-Za-z]' && row == ''
      output->add(character)
    else
      throw 'caskk: invalid combination symbol: ' .. character
    endif
  endfor
  if row != ''
    throw 'caskk: incomplete okuri prefix: ' .. row
  endif
  return join(output, '')
enddef

# Generate a romanized output sequence. The configured consonant row applies
# only to the first character, while later consonant-vowel groups use their
# own rows (for example, row m plus "itu" becomes "みつ").
def GenerateReading(text: string, first_row: string): string
  final output: list<string> = []
  var row = ''
  var input_offset = 0
  for codepoint in str2list(text, true)
    const character = nr2char(codepoint, true)
    const vowel = index(TABLE.vowels, character)
    if vowel >= 0
      const generated = row != '' ? GenerateCharacter(row, character)
        : GenerateCharacter(input_offset == 0 ? first_row : '', character)
      output->add(generated)
      row = ''
    elseif character =~ '[a-z]'
      row ..= character
      if !has_key(TABLE.rows, row)
        throw 'caskk: invalid combination symbol: ' .. row
      endif
    elseif has_key(TABLE.symbols, character) && row == ''
      output->add(TABLE.symbols[character])
    elseif character =~ '[A-Z]' && row == ''
      output->add(GenerateCharacter('', character))
    elseif character !~ '[A-Za-z]' && row == ''
      output->add(character)
    else
      throw 'caskk: invalid combination symbol: ' .. character
    endif
    input_offset += 1
  endfor
  if row != ''
    throw 'caskk: invalid combination symbol: ' .. row
  endif
  return join(output, '')
enddef

# Apply the consonant row to the initial vowel, then parse later kana rows.
# The parser has already decoded escapes, so literal * and \ remain text.
export def Generate(row: string, pattern: pattern_types.OutputPattern): pattern_types.OutputPattern
  if !has_key(TABLE.rows, row)
    throw 'caskk: unknown consonant row: ' .. row
  endif

  const characters = str2list(pattern.text, true)
  if pattern.boundary >= 0
    const before = pattern.boundary == 0 ? [] : characters[: pattern.boundary - 1]
    const after = characters[pattern.boundary :]
    const reading = GenerateReading(list2str(before, true), row)
    const okuri = GenerateOkuri(list2str(after, true))
    return pattern_types.OutputPattern.new(reading .. okuri, strchars(reading))
  endif
  return pattern_types.OutputPattern.new(GenerateReading(pattern.text, row), -1)
enddef
