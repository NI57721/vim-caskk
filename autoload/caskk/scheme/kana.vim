vim9script

import 'caskk/output_pattern.vim' as pattern_types

# Fixed output vocabulary shared by generation and its tests.
export const TABLE: dict<any> = {
  vowels: ['a', 'i', 'u', 'e', 'o'],
  rows: {
    '': ['あ', 'い', 'う', 'え', 'お'],
    x: ['ぁ', 'ぃ', 'ぅ', 'ぇ', 'ぉ'],
    xy: ['ゃ', '', 'ゅ', '', 'ょ'],
    xw: ['ゎ', '', '', '', ''],
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
  symbols: {N: 'ん', T: 'っ'},
}

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

# Apply the row to the leading vowel; subsequent vowels have no consonant.
# The parser has already decoded escapes, so literal * and \ remain text.
export def Generate(row: string, pattern: pattern_types.OutputPattern): pattern_types.OutputPattern
  if !has_key(TABLE.rows, row)
    throw 'caskk: unknown consonant row: ' .. row
  endif

  final output: list<string> = []
  var input_offset = 0
  var output_offset = 0
  var boundary = -1

  for codepoint in str2list(pattern.text, true)
    if input_offset == pattern.boundary
      boundary = output_offset
    endif

    const character = nr2char(codepoint, true)
    const generated = GenerateCharacter(input_offset == 0 ? row : '', character)

    output->add(generated)
    output_offset += strchars(generated)
    input_offset += 1
  endfor

  if input_offset == pattern.boundary
    boundary = output_offset
  endif

  return pattern_types.OutputPattern.new(join(output, ''), boundary)
enddef
