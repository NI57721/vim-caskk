vim9script

import autoload 'caskk/input/mapping.vim' as mapping

const GROUP = 'CaskkPreedit'
const ATTRIBUTES = [
  'bold', 'standout', 'underline', 'undercurl', 'underdouble',
  'underdotted', 'underdashed', 'italic', 'reverse', 'inverse',
  'strikethrough', 'nocombine',
]
const STRING_FIELDS = ['ctermfg', 'ctermbg', 'ctermul', 'guifg', 'guibg', 'guisp', 'font', 'start', 'stop']

class Highlight
  const attributes: dict<dict<bool>>
  const strings: dict<string>

  def new(attributes: dict<dict<bool>>, strings: dict<string>)
    this.attributes = deepcopy(attributes)
    this.strings = copy(strings)
  enddef
endclass

export class Input
  const sticky_key: string
  const mappings: dict<string>

  def new(this.sticky_key, mappings: dict<string>)
    this.mappings = copy(mappings)
  enddef
endclass

class Settings
  const highlight: Highlight
  const input: Input

  def new(this.highlight, this.input)
  enddef
endclass

def ParseAttributes(value: string): dict<bool>
  if toupper(trim(value)) ==# 'NONE'
    return {}
  endif
  final attributes: dict<bool> = {}
  for item in split(value, ',', true)
    const name = tolower(trim(item))
    if index(ATTRIBUTES, name) < 0
      throw 'caskk: invalid configuration: unknown highlight attribute: ' .. item
    endif
    attributes[name] = true
  endfor
  return attributes
enddef

def ParseHighlight(highlights: dict<dict<string>>): Highlight
  for role in keys(highlights)
    if role !=# 'preedit'
      throw 'caskk: invalid configuration: unknown highlight role: ' .. role
    endif
  endfor
  final attributes: dict<dict<bool>> = {
    term: {underline: true}, cterm: {underline: true}, gui: {underline: true},
  }
  final strings: dict<string> = {}
  for [name, value] in items(get(highlights, 'preedit', {}))
    if has_key(attributes, name)
      attributes[name] = ParseAttributes(value)
    elseif index(STRING_FIELDS, name) >= 0
      strings[name] = value
    else
      throw 'caskk: invalid configuration: unknown highlight field: ' .. name
    endif
  endfor
  return Highlight.new(attributes, strings)
enddef

# Dynamic values are validated and copied only at the configuration boundary.
def ReadHighlight(raw: any): dict<dict<string>>
  if type(raw) != v:t_dict
    throw 'highlight must be a dictionary'
  endif
  final highlights: dict<dict<string>> = {}
  for [role, raw_fields] in items(raw)
    if type(raw_fields) != v:t_dict
      throw 'highlight.' .. role .. ' must be a dictionary'
    endif
    final fields: dict<string> = {}
    for [name, value] in items(raw_fields)
      if type(value) != v:t_string
        throw 'highlight.' .. role .. '.' .. name .. ' must be a string'
      endif
      fields[name] = value
    endfor
    highlights[role] = fields
  endfor
  return highlights
enddef

def ReadStickyKey(raw: any): string
  if type(raw) != v:t_string
    throw 'sticky_key must be a string'
  endif
  const key: string = raw
  if key != ''
    mapping.Lhs(key)
  endif
  return key
enddef

def ReadMappings(raw: any): dict<string>
  if type(raw) != v:t_dict
    throw 'mappings must be a dictionary'
  endif
  final actions: dict<string> = {}
  final physical_keys: dict<bool> = {}
  for [key, value] in items(raw)
    if type(value) != v:t_string
      throw 'mapping action must be a string: ' .. key
    endif
    const action: string = value
    mapping.ValidateAction(action)
    const lhs = mapping.Lhs(key)
    if has_key(physical_keys, lhs)
      throw 'duplicate physical mapping: ' .. key
    endif
    physical_keys[lhs] = true
    actions[key] = action
  endfor
  return actions
enddef

def Parse(options: dict<any>): Settings
  for section in keys(options)
    if index(['highlight', 'sticky_key', 'mappings'], section) < 0
      throw 'unknown section: ' .. section
    endif
  endfor
  const highlight = ParseHighlight(ReadHighlight(get(options, 'highlight', {})))
  const sticky_key = ReadStickyKey(get(options, 'sticky_key', ''))
  const actions = ReadMappings(get(options, 'mappings', {}))
  return Settings.new(highlight, Input.new(sticky_key, actions))
enddef

var current = Parse({})

def Install(highlight: Highlight)
  # Heterogeneous dictionaries are confined to the native hlset() boundary.
  if hlset([{name: GROUP, cleared: true}, {
      name: GROUP, term: highlight.attributes.term,
      cterm: highlight.attributes.cterm, gui: highlight.attributes.gui,
    }]) != 0
    throw 'cannot apply highlight attributes'
  endif
  for [name, value] in items(highlight.strings)
    final definition: dict<string> = {name: GROUP}
    definition[name] = value
    if hlset([definition]) != 0
      throw 'cannot apply highlight field: ' .. name
    endif
  endfor
enddef

export def ApplyHighlight()
  Install(current.highlight)
enddef

export def GetInput(): Input
  return Input.new(current.input.sticky_key, current.input.mappings)
enddef

export def Configure(options: dict<any>)
  var parsed: Settings
  try
    parsed = Parse(options)
  catch
    const reason = v:exception
    if stridx(reason, 'caskk: invalid configuration:') == 0
      throw reason
    endif
    throw 'caskk: invalid configuration: ' .. reason
  endtry
  const previous = hlget(GROUP)
  try
    Install(parsed.highlight)
  catch
    const reason = v:exception
    hlset([{name: GROUP, cleared: true}])
    hlset(previous)
    throw 'caskk: invalid configuration: ' .. reason
  endtry
  current = parsed
enddef

augroup caskk_highlight
  autocmd!
  autocmd ColorScheme * ApplyHighlight()
augroup END
