vim9script

export const HIRAGANA = 'Hiragana'
export const ABBREVIATION = 'Abbreviation'
export const KATAKANA = 'Katakana'
export const HALFWIDTH_KATAKANA = 'HalfwidthKatakana'
export const FULLWIDTH_ALPHANUMERIC = 'FullwidthAlphanumeric'

const MODES = [HIRAGANA, ABBREVIATION, KATAKANA, HALFWIDTH_KATAKANA,
  FULLWIDTH_ALPHANUMERIC]

export const LABEL_NAMES: dict<string> = {
  hiragana: HIRAGANA,
  abbreviation: ABBREVIATION,
  katakana: KATAKANA,
  halfwidth_katakana: HALFWIDTH_KATAKANA,
  fullwidth_alphanumeric: FULLWIDTH_ALPHANUMERIC,
}

export const DEFAULT_LABELS: dict<string> = {
  hiragana: 'あ',
  abbreviation: 'ab',
  katakana: 'ア',
  halfwidth_katakana: 'ｱ',
  fullwidth_alphanumeric: 'Ａ',
}

const HALFWIDTH: dict<string> = {
  '。': '｡', '、': '､', '・': '･', 'ー': 'ｰ', '「': '｢', '」': '｣',
  'ァ': 'ｧ', 'ア': 'ｱ', 'ィ': 'ｨ', 'イ': 'ｲ', 'ゥ': 'ｩ', 'ウ': 'ｳ',
  'ェ': 'ｪ', 'エ': 'ｴ', 'ォ': 'ｫ', 'オ': 'ｵ', 'カ': 'ｶ', 'ガ': 'ｶﾞ',
  'キ': 'ｷ', 'ギ': 'ｷﾞ', 'ク': 'ｸ', 'グ': 'ｸﾞ', 'ケ': 'ｹ', 'ゲ': 'ｹﾞ',
  'コ': 'ｺ', 'ゴ': 'ｺﾞ', 'サ': 'ｻ', 'ザ': 'ｻﾞ', 'シ': 'ｼ', 'ジ': 'ｼﾞ',
  'ス': 'ｽ', 'ズ': 'ｽﾞ', 'セ': 'ｾ', 'ゼ': 'ｾﾞ', 'ソ': 'ｿ', 'ゾ': 'ｿﾞ',
  'タ': 'ﾀ', 'ダ': 'ﾀﾞ', 'チ': 'ﾁ', 'ヂ': 'ﾁﾞ', 'ッ': 'ｯ', 'ツ': 'ﾂ',
  'ヅ': 'ﾂﾞ', 'テ': 'ﾃ', 'デ': 'ﾃﾞ', 'ト': 'ﾄ', 'ド': 'ﾄﾞ', 'ナ': 'ﾅ',
  'ニ': 'ﾆ', 'ヌ': 'ﾇ', 'ネ': 'ﾈ', 'ノ': 'ﾉ', 'ハ': 'ﾊ', 'バ': 'ﾊﾞ',
  'パ': 'ﾊﾟ', 'ヒ': 'ﾋ', 'ビ': 'ﾋﾞ', 'ピ': 'ﾋﾟ', 'フ': 'ﾌ', 'ブ': 'ﾌﾞ',
  'プ': 'ﾌﾟ', 'ヘ': 'ﾍ', 'ベ': 'ﾍﾞ', 'ペ': 'ﾍﾟ', 'ホ': 'ﾎ', 'ボ': 'ﾎﾞ',
  'ポ': 'ﾎﾟ', 'マ': 'ﾏ', 'ミ': 'ﾐ', 'ム': 'ﾑ', 'メ': 'ﾒ', 'モ': 'ﾓ',
  'ャ': 'ｬ', 'ヤ': 'ﾔ', 'ュ': 'ｭ', 'ユ': 'ﾕ', 'ョ': 'ｮ', 'ヨ': 'ﾖ',
  'ラ': 'ﾗ', 'リ': 'ﾘ', 'ル': 'ﾙ', 'レ': 'ﾚ', 'ロ': 'ﾛ', 'ヮ': 'ﾜ',
  'ワ': 'ﾜ', 'ヰ': 'ｲﾞ', 'ヱ': 'ｴﾞ', 'ヲ': 'ｦ', 'ン': 'ﾝ', 'ヴ': 'ｳﾞ',
  'ヵ': 'ｶ', 'ヶ': 'ｹ', 'ヷ': 'ﾜﾞ', 'ヸ': 'ｲﾞ', 'ヹ': 'ｴﾞ', 'ヺ': 'ｦﾞ',
}

def IsKana(codepoint: number): bool
  return (codepoint >= 0x3041 && codepoint <= 0x3096)
    || codepoint == 0x309D || codepoint == 0x309E
enddef

def Katakana(character: string, codepoint: number): string
  return IsKana(codepoint) ? nr2char(codepoint + 0x60, true) : character
enddef

def Halfwidth(character: string): string
  return get(HALFWIDTH, character, character)
enddef

def FullwidthAlphanumeric(character: string, codepoint: number): string
  if codepoint == 0x20
    return '　'
  endif
  return codepoint >= 0x21 && codepoint <= 0x7e
    ? nr2char(codepoint + 0xfee0, true) : character
enddef

export def IsValid(mode: string): bool
  return index(MODES, mode) >= 0
enddef

export def LabelName(mode: string): string
  for [name, value] in items(LABEL_NAMES)
    if value ==# mode
      return name
    endif
  endfor
  throw 'caskk: unknown input mode: ' .. mode
enddef

export def Transition(current: string, requested: string): string
  if !IsValid(current) || !IsValid(requested)
    throw 'caskk: unknown input mode'
  endif
  return current == requested && current != HIRAGANA ? HIRAGANA : requested
enddef

export def Render(text: string, mode: string): string
  if !IsValid(mode)
    throw 'caskk: unknown input mode'
  endif
  if mode == HIRAGANA || mode == ABBREVIATION
    return text
  endif

  final output: list<string> = []
  for codepoint in str2list(text, true)
    const character = nr2char(codepoint, true)
    if mode == FULLWIDTH_ALPHANUMERIC
      output->add(FullwidthAlphanumeric(character, codepoint))
    else
      const katakana = Katakana(character, codepoint)
      output->add(mode == HALFWIDTH_KATAKANA ? Halfwidth(katakana) : katakana)
    endif
  endfor
  return join(output, '')
enddef
