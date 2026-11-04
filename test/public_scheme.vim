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
