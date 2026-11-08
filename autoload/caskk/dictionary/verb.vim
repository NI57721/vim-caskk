vim9script
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/dictionary/stem.vim' as stem

const ENDINGS: dict<string> = {
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
  '@verb-5-wa': 'わいうえおっ',
  '@verb-5-wa-iu': 'わいうえお',
  '@verb-5-wa-yuu': 'わいうえお',
  '@verb-1-kami-a': 'るれろよなまさてたらずぬん',
  '@verb-1-kami-k': 'るれろよなまさてたらずぬん',
  '@verb-1-kami-g': 'るれろよなまさてたらずぬん',
  '@verb-1-kami-z': 'るれろよなまさてたらずぬん',
  '@verb-1-kami-t': 'るれろよなまさてたらずぬん',
  '@verb-1-kami-n': 'るれろよなまさてたらずぬん',
  '@verb-1-kami-h': 'るれろよなまさてたらずぬん',
  '@verb-1-kami-b': 'るれろよなまさてたらずぬん',
  '@verb-1-kami-m': 'るれろよなまさてたらずぬん',
  '@verb-1-kami-r': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-a': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-k': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-g': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-s': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-z': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-t': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-d': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-n': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-h': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-b': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-m': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-r': 'るれろよなまさてたらずぬん',
  '@verb-1-shimo-r-kureru': 'るれよなまさてたらずぬん',
  '@verb-irregular-k': 'こきくるれいよなまさてたらずぬん',
  '@verb-irregular-s': 'さしすせそるれろよなまてたらずぬん',
  '@verb-irregular-z': 'ざじずぜぞるれろよなまてたらぬん',
  '@verb-classical-4-k': 'かきくけこ',
  '@verb-classical-4-g': 'がぎぐげご',
  '@verb-classical-4-s': 'さしすせそ',
  '@verb-classical-4-t': 'たちつてと',
  '@verb-classical-4-h-u': 'はひうへほ',
  '@verb-classical-4-h-hu': 'はひふへほ',
  '@verb-classical-4-b': 'ばびぶべぼ',
  '@verb-classical-4-m': 'まみむめも',
  '@verb-classical-4-r': 'らりるれろ',
  '@verb-classical-2-kami-k': 'きくるれよ',
  '@verb-classical-2-kami-g': 'ぎぐるれよ',
  '@verb-classical-2-kami-t': 'ちつるれよ',
  '@verb-classical-2-kami-d': 'ぢづるれよ',
  '@verb-classical-2-kami-h': 'ひふるれよ',
  '@verb-classical-2-kami-b': 'びぶるれよ',
  '@verb-classical-2-kami-m': 'みむるれよ',
  '@verb-classical-2-kami-y': 'いゆるれよ',
  '@verb-classical-2-kami-r': 'りるれよ',
  '@verb-classical-2-shimo-a': 'えうるれよ',
  '@verb-classical-2-shimo-k': 'けくるれよ',
  '@verb-classical-2-shimo-g': 'げぐるれよ',
  '@verb-classical-2-shimo-s': 'せするれよ',
  '@verb-classical-2-shimo-z': 'ぜずるれよ',
  '@verb-classical-2-shimo-t': 'てつるれよ',
  '@verb-classical-2-shimo-d-zu': 'ぜずるれよ',
  '@verb-classical-2-shimo-d-du': 'でづるれよ',
  '@verb-classical-2-shimo-n': 'ねぬるれよ',
  '@verb-classical-2-shimo-h': 'へふるれよ',
  '@verb-classical-2-shimo-b': 'べぶるれよ',
  '@verb-classical-2-shimo-m': 'めむるれよ',
  '@verb-classical-2-shimo-y': 'えゆるれよ',
  '@verb-classical-2-shimo-r': 'れるよ',
  '@verb-classical-2-shimo-w': 'ゑうるれよ',
  '@verb-classical-irregular-k': 'こきくるれ',
  '@verb-classical-irregular-s': 'さしすせるれよ',
  '@verb-classical-irregular-z': 'ざじずぜるれよ',
  '@verb-classical-irregular-n': 'なにぬね',
  '@verb-classical-irregular-r': 'らりるれ',
}

export def Lookup(entries: dict<dictionary.Entry>, preferences: user_state.State, reading: string, okuri: string, database: dict_index.Database): list<dictionary.Candidate>
  if okuri == ''
    return []
  endif
  final result: list<dictionary.Candidate> = []
  for candidate in stem.Lookup(entries, preferences, reading, database)
    var matched = false
    for annotation in candidate.annotations
      for tag in split(annotation, '[[:space:];]\+')
        if has_key(ENDINGS, tag) && stridx(ENDINGS[tag], strcharpart(okuri, 0, 1)) >= 0
          matched = true
        endif
      endfor
    endfor
    if matched
      result->add(candidate)
    endif
  endfor
  return result
enddef
