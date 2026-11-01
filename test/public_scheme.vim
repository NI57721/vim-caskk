vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/session.vim' as session

final suite = themis#suite('public input scheme API')
const assert = themis#helper('assert')

suite.registered_scheme_composes_normal_input_and_prioritizes_specials = (): void => {
  Caskk.RegisterInputScheme('public-normal', {k: 'k'}, {a: 'a'})
  const ordinary = session.Session.new(Caskk.GetInputScheme('public-normal'))
  ordinary.Feed('k')
  assert.equals(ordinary.Feed('a')[0].text, 'か')
  Caskk.RegisterInputScheme('public-special', {k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['k', 'a'], '特別'),
  ])
  const special = session.Session.new(Caskk.GetInputScheme('public-special'))
  special.Feed('k')
  assert.equals(special.Feed('a')[0].text, '特別')
}

suite.reregistration_does_not_change_an_existing_session_or_pending_input = (): void => {
  Caskk.RegisterInputScheme('public-replace', {k: 'k'}, {a: 'a'})
  const previous = session.Session.new(Caskk.GetInputScheme('public-replace'))
  previous.Feed('k')
  Caskk.RegisterInputScheme('public-replace', {k: 'n'}, {a: 'a'})
  const current = session.Session.new(Caskk.GetInputScheme('public-replace'))
  current.Feed('k')
  assert.equals(previous.Feed('a')[0].text, 'か')
  assert.equals(current.Feed('a')[0].text, 'な')
}

suite.failed_reregistration_keeps_the_previous_scheme_available = (): void => {
  Caskk.RegisterInputScheme('public-invalid', {k: 'k'}, {a: 'a'})
  var caught = ''
  try
    Caskk.RegisterInputScheme('public-invalid', {k: 'n'}, {a: 'a**'})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: output pattern contains multiple latent okuri boundaries')
  const ime = session.Session.new(Caskk.GetInputScheme('public-invalid'))
  ime.Feed('k')
  assert.equals(ime.Feed('a')[0].text, 'か')
}

suite.highlight_configuration_does_not_reset_registered_schemes = (): void => {
  Caskk.RegisterInputScheme('public-config', {k: 'k'}, {a: 'a'})
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
