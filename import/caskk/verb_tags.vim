vim9script

export const ENDINGS: dict<string> = {
  '@verb-5-k': 'かきくけこい',
  '@verb-5-k-iku': 'かきくけこっ',
  '@verb-5-k-yuku': 'かきくけこっ',
  '@verb-5-g': 'がぎぐげごい',
  '@verb-5-s': 'さしすせそ',
  '@verb-5-t': 'たちつてとっ',
  '@verb-5-n': 'なにぬねのん',
  '@verb-5-b': 'ばびぶべぼん',
  '@verb-5-m': 'まみむめもん',
  '@verb-5-r': 'らりるれろっ',
  '@verb-5-r-aru': 'らりるれろっい',
  '@verb-5-w': 'わいうえおっ',
  '@verb-5-w-tou': 'わいうえお',
  '@verb-1': 'るれろよなまさてたらずぬんち',
  '@verb-1-uru': 'るれ',
  '@verb-1-kureru': 'るれよなまさてたらずぬんち',
  '@verb-henkaku-k': 'こきくるれいよなまさてたらずぬんち',
  '@verb-henkaku-s': 'さしすせそるれろよなまてたらずぬんち',
  '@verb-henkaku-z': 'ざじずぜぞるれろよなまてたらぬんち',
  '@verb-bungo-4-k': 'かきくけこ',
  '@verb-bungo-4-g': 'がぎぐげご',
  '@verb-bungo-4-s': 'さしすせそ',
  '@verb-bungo-4-t': 'たちつてと',
  '@verb-bungo-4-h-u': 'はひうへほ',
  '@verb-bungo-4-h-hu': 'はひふへほ',
  '@verb-bungo-4-b': 'ばびぶべぼ',
  '@verb-bungo-4-m': 'まみむめも',
  '@verb-bungo-4-r': 'らりるれろ',
  '@verb-bungo-2-kami-k': 'きくるれよ',
  '@verb-bungo-2-kami-g': 'ぎぐるれよ',
  '@verb-bungo-2-kami-t': 'ちつるれよ',
  '@verb-bungo-2-kami-d': 'ぢづるれよ',
  '@verb-bungo-2-kami-h': 'ひふるれよ',
  '@verb-bungo-2-kami-b': 'びぶるれよ',
  '@verb-bungo-2-kami-m': 'みむるれよ',
  '@verb-bungo-2-kami-y': 'いゆるれよ',
  '@verb-bungo-2-kami-r': 'りるれよ',
  '@verb-bungo-2-shimo-a': 'えうるれよ',
  '@verb-bungo-2-shimo-k': 'けくるれよ',
  '@verb-bungo-2-shimo-g': 'げぐるれよ',
  '@verb-bungo-2-shimo-s': 'せするれよ',
  '@verb-bungo-2-shimo-z': 'ぜずるれよ',
  '@verb-bungo-2-shimo-t': 'てつるれよ',
  '@verb-bungo-2-shimo-d-zu': 'ぜずるれよ',
  '@verb-bungo-2-shimo-d-du': 'でづるれよ',
  '@verb-bungo-2-shimo-n': 'ねぬるれよ',
  '@verb-bungo-2-shimo-h': 'へふるれよ',
  '@verb-bungo-2-shimo-b': 'べぶるれよ',
  '@verb-bungo-2-shimo-m': 'めむるれよ',
  '@verb-bungo-2-shimo-y': 'えゆるれよ',
  '@verb-bungo-2-shimo-r': 'れるよ',
  '@verb-bungo-2-shimo-w': 'ゑうるれよ',
  '@verb-bungo-henkaku-k': 'こきくるれ',
  '@verb-bungo-henkaku-s': 'さしすせるれよ',
  '@verb-bungo-henkaku-z': 'ざじずぜるれよ',
  '@verb-bungo-henkaku-n': 'なにぬね',
  '@verb-bungo-henkaku-r': 'らりるれ',
}

export def HasVerb(annotations: list<string>): bool
  for annotation in annotations
    for tag in split(annotation, '[[:space:];]\+')
      if has_key(ENDINGS, tag)
        return true
      endif
    endfor
  endfor
  return false
enddef

const LABELS: dict<string> = {
  '@adj': '形',
  '@verb-1-kureru': '下一(呉)',
  '@verb-1-uru': '一段(得)',
  '@verb-5-k': 'カ五',
  '@verb-5-k-iku': 'カ五(行)',
  '@verb-5-k-yuku': 'カ五(往)',
  '@verb-5-g': 'ガ五',
  '@verb-5-s': 'サ五',
  '@verb-5-t': 'タ五',
  '@verb-5-n': 'ナ五',
  '@verb-5-b': 'バ五',
  '@verb-5-m': 'マ五',
  '@verb-5-r': 'ラ五',
  '@verb-5-r-aru': 'ラ五(有)',
  '@verb-5-w': 'ワ五',
  '@verb-5-w-tou': 'ワ五(問)',
  '@verb-henkaku-k': 'カ変',
  '@verb-henkaku-s': 'サ変',
  '@verb-henkaku-z': 'ザ変',
  '@verb-bungo-4-k': '文カ四',
  '@verb-bungo-4-g': '文ガ四',
  '@verb-bungo-4-s': '文サ四',
  '@verb-bungo-4-t': '文タ四',
  '@verb-bungo-4-h-u': '文ハ四(う)',
  '@verb-bungo-4-h-hu': '文ハ四(ふ)',
  '@verb-bungo-4-b': '文バ四',
  '@verb-bungo-4-m': '文マ四',
  '@verb-bungo-4-r': '文ラ四',
  '@verb-bungo-2-kami-k': '文カ上二',
  '@verb-bungo-2-kami-g': '文ガ上二',
  '@verb-bungo-2-kami-t': '文タ上二',
  '@verb-bungo-2-kami-d': '文ダ上二',
  '@verb-bungo-2-kami-h': '文ハ上二',
  '@verb-bungo-2-kami-b': '文バ上二',
  '@verb-bungo-2-kami-m': '文マ上二',
  '@verb-bungo-2-kami-y': '文ヤ上二',
  '@verb-bungo-2-kami-r': '文ラ上二',
  '@verb-bungo-2-shimo-a': '文ア下二',
  '@verb-bungo-2-shimo-k': '文カ下二',
  '@verb-bungo-2-shimo-g': '文ガ下二',
  '@verb-bungo-2-shimo-s': '文サ下二',
  '@verb-bungo-2-shimo-z': '文ザ下二',
  '@verb-bungo-2-shimo-t': '文タ下二',
  '@verb-bungo-2-shimo-d-zu': '文ダ下二(ず)',
  '@verb-bungo-2-shimo-d-du': '文ダ下二(づ)',
  '@verb-bungo-2-shimo-n': '文ナ下二',
  '@verb-bungo-2-shimo-h': '文ハ下二',
  '@verb-bungo-2-shimo-b': '文バ下二',
  '@verb-bungo-2-shimo-m': '文マ下二',
  '@verb-bungo-2-shimo-y': '文ヤ下二',
  '@verb-bungo-2-shimo-r': '文ラ下二',
  '@verb-bungo-2-shimo-w': '文ワ下二',
  '@verb-bungo-henkaku-k': '文カ変',
  '@verb-bungo-henkaku-s': '文サ変',
  '@verb-bungo-henkaku-z': '文ザ変',
  '@verb-bungo-henkaku-n': '文ナ変',
  '@verb-bungo-henkaku-r': '文ラ変',
}

export def Label(tag: string, reading: string): string
  if tag !=# '@verb-1'
    return LABELS[tag]
  endif
  if reading =~# '[いきぎしじちぢにひびぴみりゐ]$'
    return '上一'
  endif
  if reading =~# '[えけげせぜてでねへべぺめれゑ]$'
    return '下一'
  endif
  return '一段'
enddef

export def IsConjugationTag(token: string): bool
  return token ==# '@adj' || has_key(ENDINGS, token)
enddef

export def WithoutTags(annotation: string, rejected: list<string>): string
  if empty(rejected)
    return annotation
  endif
  const separator = '[[:space:];]'
  const tag = '\%(' .. join(rejected, '\|') .. '\)'
  const run = tag .. '\%(' .. separator .. '\+' .. tag .. '\)*'
  # Remove the preceding separator at the end, otherwise the following separator.
  const pattern = separator .. '\+' .. run .. separator .. '*$'
    .. '\|\%(^\|' .. separator .. '\@<=\)' .. run .. '\%(' .. separator .. '\+\|$\)'
  return substitute(annotation, '\C' .. pattern, '', 'g')
enddef
