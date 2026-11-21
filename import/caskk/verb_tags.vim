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
