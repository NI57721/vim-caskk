vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/session.vim' as session

final suite = themis#suite('public input scheme API')
const assert = themis#helper('assert')

suite.registration_accepts_one_input_scheme_definition = (): void => {
  Caskk.RegisterInputScheme({name: 'public-object', consonants: {k: 'k'},
    combinations: {a: 'a'}, specials: {}})
  const ime = session.Session.new(Caskk.GetInputScheme('public-object'))
  ime.Feed('k')
  assert.equals(ime.Feed('a')[0].text, 'か')
}

suite.invalid_definition_does_not_replace_a_registered_scheme = (): void => {
  Caskk.RegisterInputScheme({name: 'public-validated', consonants: {k: 'k'},
    combinations: {a: 'a'}})
  var caught = ''
  try
    Caskk.RegisterInputScheme({name: 'public-validated', consonants: {k: 'n'}})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: invalid input scheme: combinations must be a dictionary')
  caught = ''
  try
    Caskk.RegisterInputScheme({name: 'public-validated', consonants: {k: 1},
      combinations: {a: 'a'}})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: invalid input scheme: consonants values must be strings')
  const ime = session.Session.new(Caskk.GetInputScheme('public-validated'))
  ime.Feed('k')
  assert.equals(ime.Feed('a')[0].text, 'か')
}

suite.registered_scheme_composes_normal_input_and_prioritizes_specials = (): void => {
  Caskk.RegisterInputScheme({name: 'public-normal', consonants: {k: 'k'}, combinations: {a: 'a'}})
  const ordinary = session.Session.new(Caskk.GetInputScheme('public-normal'))
  ordinary.Feed('k')
  assert.equals(ordinary.Feed('a')[0].text, 'か')
  Caskk.RegisterInputScheme({name: 'public-special', consonants: {k: 'k'}, combinations: {a: 'a'},
    specials: {'ka': '特別'}})
  const special = session.Session.new(Caskk.GetInputScheme('public-special'))
  special.Feed('k')
  assert.equals(special.Feed('a')[0].text, '特別')
}

suite.special_rules_accept_key_sequences_as_a_dictionary = (): void => {
  Caskk.RegisterInputScheme({name: 'public-special-dictionary', consonants: {}, combinations: {},
    specials: {jsn: 'ません', "\<C-K>": 'ケー', "\<F10>jsn": '複合',
      '<C-K>': '文字列', '\<C-K>': 'バックスラッシュ'}})
  const compiled = Caskk.GetInputScheme('public-special-dictionary')
  assert.equals(len(compiled.specials), 5)
  const ime = session.Session.new(compiled)
  assert.equals(ime.Feed('j'), [])
  assert.equals(ime.Feed('s'), [])
  assert.equals(ime.Feed('n')[0].text, 'ません')
  assert.equals(session.Session.new(compiled).Feed('<C-K>')[0].text, 'ケー')
  const mixed = session.Session.new(compiled)
  assert.equals(mixed.Feed('<F10>'), [])
  assert.equals(mixed.Feed('j'), [])
  assert.equals(mixed.Feed('s'), [])
  assert.equals(mixed.Feed('n')[0].text, '複合')
  const literal = session.Session.new(compiled)
  assert.equals(literal.Feed('<'), [])
  assert.equals(literal.Feed('C'), [])
  assert.equals(literal.Feed('-'), [])
  assert.equals(literal.Feed('K'), [])
  assert.equals(literal.Feed('>')[0].text, '文字列')
  const backslash = session.Session.new(compiled)
  assert.equals(backslash.Feed('\'), [])
  assert.equals(backslash.Feed('<'), [])
  assert.equals(backslash.Feed('C'), [])
  assert.equals(backslash.Feed('-'), [])
  assert.equals(backslash.Feed('K'), [])
  assert.equals(backslash.Feed('>')[0].text, 'バックスラッシュ')
}

suite.public_scheme_requires_valid_consonant_identifiers_and_one_key_combinations = (): void => {
  for definition in [
    {name: 'invalid-consonant-row', consonants: {k: 'xz'}, combinations: {a: 'a'}},
    {name: 'invalid-consonant-name', consonants: {k: 'q'}, combinations: {a: 'a'}},
    {name: 'duplicate-normalized-consonant-key', consonants: {k: 'k', K: 's'}, combinations: {a: 'a'}},
    {name: 'invalid-combination-token', consonants: {}, combinations: {'<C-K>': 'a'}},
    {name: 'invalid-combination-backslash-text', consonants: {}, combinations: {'\<C-K>': 'a'}},
    {name: 'invalid-combination-sequence', consonants: {}, combinations: {ab: 'a'}},
    {name: 'duplicate-normalized-combination-key', consonants: {}, combinations: {a: 'a', A: 'i'}},
    {name: 'invalid-combination-value', consonants: {}, combinations: {a: 'ka'}},
    {name: 'invalid-combination-tail', consonants: {}, combinations: {a: 'ak'}},
    {name: 'invalid-combination-escape', consonants: {}, combinations: {a: 'a\*'}},
  ]
    var caught = ''
    try
      Caskk.RegisterInputScheme(definition)
    catch
      caught = v:exception
    endtry
    assert.equals(stridx(caught, 'caskk: invalid input scheme:'), 0)
  endfor

  Caskk.RegisterInputScheme({name: 'valid-special-combination-key', consonants: {},
    combinations: {"\<C-K>": 'e*Tte'}})
  const compiled = Caskk.GetInputScheme('valid-special-combination-key')
  assert.equals(has_key(compiled.table.combinations, '<C-K>'), true)
}

suite.public_consonants_accept_multi_character_kana_identifiers = (): void => {
  Caskk.RegisterInputScheme({name: 'public-wh-consonant', consonants: {w: 'wh'},
    combinations: {i: 'i'}})
  const wh = session.Session.new(Caskk.GetInputScheme('public-wh-consonant'))
  wh.Feed('w')
  assert.equals(wh.Feed('i')[0].text, 'うぃ')

  Caskk.RegisterInputScheme({name: 'public-xy-consonant', consonants: {x: 'xy'},
    combinations: {a: 'a'}})
  const xy = session.Session.new(Caskk.GetInputScheme('public-xy-consonant'))
  xy.Feed('x')
  assert.equals(xy.Feed('a')[0].text, 'ゃ')
}

suite.public_consonant_keys_accept_sequences_and_distinguish_literal_key_text = (): void => {
  Caskk.RegisterInputScheme({name: 'consonant-key-forms',
    consonants: {wg: 'w', "\<C-K>": 'k', '<C-K>': 's', '\<C-K>': 'z'},
    combinations: {a: 'a'}})
  const compiled = Caskk.GetInputScheme('consonant-key-forms')
  assert.equals(len(compiled.table.consonants), 4)
}

suite.special_output_rejects_more_than_one_latent_boundary_on_registration = (): void => {
  Caskk.RegisterInputScheme({name: 'special-boundary-limit', consonants: {}, combinations: {},
    specials: {x: '前*送り'}})
  var caught = ''
  try
    Caskk.RegisterInputScheme({name: 'special-boundary-limit', consonants: {}, combinations: {},
      specials: {x: '前*送り*後'}})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: output pattern contains multiple latent okuri boundaries')
  const old = Caskk.GetInputScheme('special-boundary-limit').specials[0].output
  assert.equals(old.text, '前送り')
  assert.equals(old.boundary, 1)
}

suite.nasal_and_sokuon_consonant_values_emit_kana_directly = (): void => {
  Caskk.RegisterInputScheme({name: 'public-kana-consonants', consonants: {q: 'N', l: 'T'}, combinations: {}})
  const engine = session.Session.new(Caskk.GetInputScheme('public-kana-consonants'))
  const nasal = engine.Feed('q')
  assert.equals(len(nasal), 1)
  assert.equals(nasal[0].text, 'ん')
  const sokuon = engine.Feed('l')
  assert.equals(len(sokuon), 1)
  assert.equals(sokuon[0].text, 'っ')
}

suite.reregistration_does_not_change_an_existing_session_or_pending_input = (): void => {
  Caskk.RegisterInputScheme({name: 'public-replace', consonants: {k: 'k'}, combinations: {a: 'a'}})
  const previous = session.Session.new(Caskk.GetInputScheme('public-replace'))
  previous.Feed('k')
  Caskk.RegisterInputScheme({name: 'public-replace', consonants: {k: 'n'}, combinations: {a: 'a'}})
  const current = session.Session.new(Caskk.GetInputScheme('public-replace'))
  current.Feed('k')
  assert.equals(previous.Feed('a')[0].text, 'か')
  assert.equals(current.Feed('a')[0].text, 'な')
}

suite.failed_reregistration_keeps_the_previous_scheme_available = (): void => {
  Caskk.RegisterInputScheme({name: 'public-invalid', consonants: {k: 'k'}, combinations: {a: 'a'}})
  var caught = ''
  try
    Caskk.RegisterInputScheme({name: 'public-invalid', consonants: {k: 'n'}, combinations: {a: 'a**'}})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: output pattern contains multiple latent okuri boundaries')
  const ime = session.Session.new(Caskk.GetInputScheme('public-invalid'))
  ime.Feed('k')
  assert.equals(ime.Feed('a')[0].text, 'か')
}

suite.highlight_configuration_does_not_reset_registered_schemes = (): void => {
  Caskk.RegisterInputScheme({name: 'public-config', consonants: {k: 'k'}, combinations: {a: 'a'}})
  Caskk.Config({})
  const ime = session.Session.new(Caskk.GetInputScheme('public-config'))
  ime.Feed('k')
  assert.equals(ime.Feed('a')[0].text, 'か')
}

suite.unknown_scheme_name_reports_an_error = (): void => {
  var caught = ''
  try
    Caskk.GetInputScheme('public-missing')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: unknown input scheme: public-missing')
}

def TypeText(name: string, keys: string): string
  const ime = session.Session.new(Caskk.GetInputScheme(name))
  var text = ''
  for key in split(keys, '\zs')
    for result in ime.Feed(key == ' ' ? '<Space>' : key)
      text ..= result.text
    endfor
  endfor
  for result in ime.Commit()
    text ..= result.text
  endfor
  return text
enddef

suite.roman_is_available_without_registration = (): void => {
  for [keys, expected] in [
    ['aiueo', 'あいうえお'], ['nihongo', 'にほんご'], ['kanji', 'かんじ'],
    ["kon'nichiha", 'こんにちは'], ['nn', 'ん'], ["n'ya", 'んや'], ['n', 'ん'],
    ['kya', 'きゃ'], ['ssya', 'っしゃ'], ['kkka', 'っっか'], ['ccha', 'っちゃ'],
    ['shi', 'し'], ['chi', 'ち'], ['tsu', 'つ'], ['fu', 'ふ'], ['ji', 'じ'],
    ['kyi', 'き'], ['nyi', 'に'], ['dhi', 'でぃ'], ['tha', 'てゃ'],
    ['xtu', 'っ'], ['xtsu', 'っ'], ['ltu', 'っ'], ['ltsu', 'っ'],
    ['lalyalwa', 'ぁゃゎ'], ['xwixwe', 'ゐゑ'], ['lwilwe', 'ゐゑ'], ['whu', 'う'],
    ['.,-;[]', '。、ー；「」']]
    assert.equals(TypeText('roman', keys), expected, keys)
  endfor
  const ime = session.Session.new(Caskk.GetInputScheme('roman'))
  assert.equals(ime.Feed('n'), [])
  assert.equals(ime.Feed('a')[0].text, 'な')
}

suite.roman_base_merges_each_map_and_deletes_inherited_rules = (): void => {
  Caskk.RegisterInputScheme({name: 'roman-custom', base: 'roman',
    consonants: {K: 's', kk: v:null}, combinations: {i: 'a'},
    specials: {'.': v:null, zh: '左'}})
  assert.equals(TypeText('roman-custom', 'ka'), 'さ')
  assert.equals(TypeText('roman-custom', 'ki'), 'さ')
  assert.equals(TypeText('roman-custom', 'shi'), 'しゃ')
  assert.equals(TypeText('roman-custom', 'kka'), 'kさ')
  assert.equals(TypeText('roman-custom', '.zh'), '.左')
  assert.equals(TypeText('roman', 'kika.'), 'きか。')
  Caskk.RegisterInputScheme({name: 'roman-custom', base: 'roman', specials: {ka: '蚊'}})
  assert.equals(TypeText('roman-custom', 'ki.ka'), 'き。蚊')
  Caskk.RegisterInputScheme({name: 'roman-minimal', base: 'roman'})
  assert.equals(TypeText('roman-minimal', 'kanji'), 'かんじ')
}

suite.invalid_roman_customization_preserves_previous_registration = (): void => {
  Caskk.RegisterInputScheme({name: 'roman-atomic', base: 'roman'})
  for override in [
    {base: 1}, {base: 'missing'}, {base: 'roman', consonants: []},
    {base: 'roman', consonants: {k: 1}}, {base: 'roman', consonants: {k: 'invalid'}},
    {base: 'roman', consonants: {k: 'k', K: 's'}},
    {base: 'roman', combinations: {a: 'a', A: 'i'}},
    {base: 'roman', specials: {ka: 'か*け*る'}},
    {base: 'roman', combinations: {a: 'ak'}}]
    var caught = ''
    try
      Caskk.RegisterInputScheme(extend({name: 'roman-atomic'}, override))
    catch
      caught = v:exception
    endtry
    assert.equals(caught != '', true, string(override))
    assert.equals(TypeText('roman-atomic', 'ka'), 'か')
  endfor
}


suite.roman_omits_optional_special_spellings_and_symbols = (): void => {
  const keys = mapnew(Caskk.GetInputScheme('roman').specials, (_, rule) => join(rule.keys, ''))
  for key in ['kyi', 'gyi', 'syi', 'zyi', 'tyi', 'dyi', 'hyi', 'byi', 'pyi', 'myi', 'ryi', 'jyi', 'cyi',
      'xka', 'xke', 'lka', 'lke', 'xwi', 'xwe', 'lwi', 'lwe',
      'z(', 'z)', 'z,', 'z-', 'z.', 'z/', 'z[', 'z]', 'z<Space>', 'zh', 'zj', 'zk', 'zl',
      'fya', 'fyi', 'fyu', 'fye', 'fyo', 'tha']
    assert.equals(index(keys, key), -1, key)
  endfor
}

suite.roman_fy_uses_the_consonant_row_and_allows_combination_overrides = (): void => {
  assert.equals(Caskk.GetInputScheme('roman').table.consonants.fy, 'fy')
  assert.equals(TypeText('roman', 'fyafyifyufyefyo'), 'ふゃふぃふゅふぇふょ')
  assert.equals(TypeText('roman', 'ffya'), 'っふゃ')
  Caskk.RegisterInputScheme({name: 'roman-fy-custom', base: 'roman', combinations: {a: 'o'}})
  assert.equals(TypeText('roman-fy-custom', 'fya'), 'ふょ')
}

suite.n_fallback_defaults_to_on_and_can_be_disabled = (): void => {
  for [name, options, nasal] in [
    ['nasal-default', {}, 'ん'],
    ['nasal-enabled', {n_fallback: true}, 'ん'],
    ['nasal-disabled', {n_fallback: false}, 'q']]
    Caskk.RegisterInputScheme(extend({name: name, consonants: {q: 'n', k: 'k'},
      combinations: {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'},
      specials: {quz: '特', kz: '継', '.': '。'}}, options))
    for [input, expected] in [
      ['qaqiquqeqo', 'なにぬねの'], ['aqka', 'あ' .. nasal .. 'か'],
      ['q.', nasal .. '。'], ['qkz', nasal .. '継'], ['q', nasal],
      ['quz', '特'], ['quka', 'ぬか']]
      assert.equals(TypeText(name, input), expected, input)
    endfor
    const ime = session.Session.new(Caskk.GetInputScheme(name))
    assert.equals(ime.Feed('q'), [])
    ime.BackspacePending()
    assert.equals(ime.Commit(), [])
  endfor
}

suite.n_fallback_resolves_long_definitions_and_replays_the_remainder = (): void => {
  Caskk.RegisterInputScheme({name: 'nasal-long', consonants: {qx: 'n', qxy: 'ny', yk: 'k', z: 'Tn'},
    combinations: {a: 'a'}, specials: {qxz: '特', '.': '。'}})
  for [input, expected] in [
    ['qxa', 'な'], ['qxya', 'にゃ'], ['qxzka', '特kあ'], ['qx', 'ん'],
    ['qxy', 'んy'], ['qxyka', 'んか'], ['qx.', 'ん。'], ['q.', 'q。'], ['za', 'っな']]
    assert.equals(TypeText('nasal-long', input), expected, input)
  endfor
  Caskk.RegisterInputScheme({name: 'nasal-prefix', consonants: {qx: 'n', qxyz: 'ny', y: 'y'},
    combinations: {a: 'a'}, specials: {'.': '。'}})
  for [input, expected] in [['qxya', 'んや'], ['qxy.', 'んy。'], ['qxy', 'んy']]
    assert.equals(TypeText('nasal-prefix', input), expected, input)
  endfor
}

suite.roman_n_rows_respect_overrides_and_n_fallback_is_validated = (): void => {
  Caskk.RegisterInputScheme({name: 'roman-n-row', base: 'roman', n_fallback: false,
    consonants: {n: 'm', q: 'N'}, combinations: {a: 'o'}})
  for [input, expected] in [
    ['na', 'も'], ['nya', 'にょ'], ['nyi', 'に'], ['n', 'n'],
    ['nn', 'ん'], ["n'", 'ん'], ['qa', 'んお']]
    assert.equals(TypeText('roman-n-row', input), expected, input)
  endfor
  Caskk.RegisterInputScheme({name: 'roman-no-fallback', base: 'roman', n_fallback: false})
  for invalid in [0, 1, 'false', v:null]
    var caught = ''
    try
      Caskk.RegisterInputScheme({name: 'roman-no-fallback', base: 'roman', n_fallback: invalid})
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: invalid input scheme: n_fallback must be a boolean')
    assert.equals(TypeText('roman-no-fallback', 'anka'), 'あnか')
  endfor
}
