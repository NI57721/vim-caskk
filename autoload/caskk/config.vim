vim9script

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

def Parse(options: dict<dict<dict<string>>>): Highlight
  for section in keys(options)
    if section !=# 'highlight'
      throw 'caskk: invalid configuration: unknown section: ' .. section
    endif
  endfor
  const highlights = get(options, 'highlight', {})
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
  Install(current)
enddef

export def Configure(options: dict<dict<dict<string>>>)
  const parsed = Parse(options)
  const previous = hlget(GROUP)
  try
    Install(parsed)
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
