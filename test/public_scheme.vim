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
    specials: {jsn: 'ません', "\<C-K>": 'ケー', "\<F10>jsn": '複合', '<C-K>': '文字列'}})
  const compiled = Caskk.GetInputScheme('public-special-dictionary')
  assert.equals(len(compiled.specials), 4)
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
