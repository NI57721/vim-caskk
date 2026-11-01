vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/buffer.vim' as buffer
import autoload 'caskk/presentation.vim' as presentation

final suite = themis#suite('highlight configuration')
const assert = themis#helper('assert')

def Reject(options: dict<dict<dict<string>>>)
  const before = hlget('CaskkPreedit')
  var caught = ''
  try
    Caskk.Config(options)
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: invalid configuration:'), 0)
  assert.equals(hlget('CaskkPreedit'), before)
enddef

def ResetConfig()
  Caskk.Config({})
enddef

def Wipe(number: number)
  execute 'silent! bwipeout! ' .. number
enddef

suite.defaults_create_the_group_without_a_user_highlight_definition = (): void => {
  defer ResetConfig()
  Caskk.Config({})
  const attributes = hlget('CaskkPreedit')[0]
  assert.equals(attributes.term.underline, true)
  assert.equals(attributes.cterm.underline, true)
  assert.equals(attributes.gui.underline, true)
}

suite.config_sets_terminal_gui_attributes_and_colors = (): void => {
  defer ResetConfig()
  const style = {term: 'reverse', cterm: 'bold,underline', gui: 'italic', ctermfg: '2', guifg: '#123456'}
  Caskk.Config({highlight: {preedit: style}})
  const attributes = hlget('CaskkPreedit')[0]
  assert.equals(attributes.term.reverse, true)
  assert.equals(attributes.cterm.bold, true)
  assert.equals(attributes.cterm.underline, true)
  assert.equals(attributes.gui.italic, true)
  assert.equals(synIDattr(hlID('CaskkPreedit'), 'fg', 'cterm'), '2')
  assert.equals(synIDattr(hlID('CaskkPreedit'), 'fg#', 'gui'), '#123456')
}

suite.omitted_fields_use_defaults_and_none_disables_attributes = (): void => {
  defer ResetConfig()
  Caskk.Config({highlight: {preedit: {cterm: 'bold'}}})
  const partial = hlget('CaskkPreedit')[0]
  assert.equals(partial.term.underline, true)
  assert.equals(partial.gui.underline, true)
  assert.equals(partial.cterm.bold, true)
  assert.equals(get(partial.cterm, 'underline', false), false)
  Caskk.Config({highlight: {preedit: {term: 'NONE', cterm: 'NONE', gui: 'NONE'}}})
  const disabled = hlget('CaskkPreedit')[0]
  assert.equals(get(disabled, 'term', {}), {})
  assert.equals(get(disabled, 'cterm', {}), {})
  assert.equals(get(disabled, 'gui', {}), {})
}

suite.unknown_sections_roles_fields_and_attributes_leave_configuration_unchanged = (): void => {
  defer ResetConfig()
  Caskk.Config({highlight: {preedit: {cterm: 'bold'}}})
  Reject({unknown: {preedit: {cterm: 'underline'}}})
  Reject({highlight: {unknown: {cterm: 'underline'}}})
  Reject({highlight: {preedit: {unknown: 'underline'}}})
  Reject({highlight: {preedit: {cterm: 'unknown'}}})
  Reject({highlight: {preedit: {cterm: 'bold||quit'}}})
}

suite.invalid_colors_roll_back_the_group_and_retained_configuration = (): void => {
  defer ResetConfig()
  Caskk.Config({highlight: {preedit: {cterm: 'bold'}}})
  Reject({highlight: {preedit: {cterm: 'reverse', ctermfg: 'caskk-invalid-color'}}})
  highlight clear CaskkPreedit
  doautocmd <nomodeline> ColorScheme
  assert.equals(hlget('CaskkPreedit')[0].cterm.bold, true)
}

suite.configuration_does_not_retain_mutable_input_dictionaries = (): void => {
  defer ResetConfig()
  final style = {cterm: 'bold'}
  Caskk.Config({highlight: {preedit: style}})
  style.cterm = 'reverse'
  highlight clear CaskkPreedit
  doautocmd <nomodeline> ColorScheme
  assert.equals(hlget('CaskkPreedit')[0].cterm.bold, true)
}

suite.colorscheme_changes_reapply_configured_attributes = (): void => {
  defer ResetConfig()
  Caskk.Config({highlight: {preedit: {term: 'reverse', cterm: 'bold', gui: 'italic'}}})
  highlight clear CaskkPreedit
  doautocmd <nomodeline> ColorScheme
  const attributes = hlget('CaskkPreedit')[0]
  assert.equals(attributes.term.reverse, true)
  assert.equals(attributes.cterm.bold, true)
  assert.equals(attributes.gui.italic, true)
}

suite.creating_a_highlighter_uses_the_current_configuration = (): void => {
  defer ResetConfig()
  const number = bufadd('')
  defer Wipe(number)
  bufload(number)
  setbufvar(number, '&buftype', 'nofile')
  setbufvar(number, '&swapfile', false)
  Caskk.Config({highlight: {preedit: {cterm: 'bold', gui: 'italic'}}})
  presentation.Highlighter.new(buffer.Writer.new(number, 1, 1))
  const attributes = hlget('CaskkPreedit')[0]
  assert.equals(attributes.cterm.bold, true)
  assert.equals(attributes.gui.italic, true)
}
