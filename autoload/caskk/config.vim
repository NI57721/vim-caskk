vim9script

import autoload 'caskk/input/mapping.vim' as mapping
import autoload 'caskk/input/mode.vim' as input_mode
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/loader.vim' as loader

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
  const keyboard_layout: string
  const keyboard_layout_overrides: dict<string>
  const mappings: dict<string>
  const entries: dict<dictionary.Entry>
  const small_tsu_okuri_as_t: bool
  const persist_input_mode: bool

  def new(this.sticky_key, this.keyboard_layout, keyboard_layout_overrides: dict<string>,
      mappings: dict<string>, entries: dict<dictionary.Entry>,
      this.small_tsu_okuri_as_t, this.persist_input_mode)
    this.keyboard_layout_overrides = copy(keyboard_layout_overrides)
    this.mappings = copy(mappings)
    this.entries = copy(entries)
  enddef
endclass

class Settings
  const highlight: Highlight
  const input: Input
  const state_path: string
  const state_auto: bool
  const registration_prefill: bool
  const registration_auto: bool
  const registration_inline: bool
  const candidate_popup: bool
  const mode_popup: bool
  const mode_popup_labels: dict<string>
  const mode_popup_markers: dict<string>
  const mode_popup_time: number

  def new(this.highlight, this.input, this.state_path, this.state_auto, this.registration_prefill,
      this.registration_auto, this.registration_inline, this.candidate_popup, this.mode_popup,
      mode_popup_labels: dict<string>, mode_popup_markers: dict<string>, this.mode_popup_time)
    this.mode_popup_labels = copy(mode_popup_labels)
    this.mode_popup_markers = copy(mode_popup_markers)
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

def ReadKeyboardLayout(raw: any): string
  if type(raw) != v:t_string || index(['US', 'JIS'], raw) < 0
    throw 'keyboard_layout must be US or JIS'
  endif
  return raw
enddef

def ReadKeyboardLayoutOverrides(raw: any): dict<string>
  if type(raw) != v:t_dict
    throw 'keyboard_layout_overrides must be a dictionary'
  endif
  final overrides: dict<string> = {}
  final symbols: dict<bool> = {}
  for [base, shifted] in items(raw)
    if strchars(base) != 1 || char2nr(base) <= 0x20 || char2nr(base) == 0x7f
      throw 'keyboard_layout_overrides keys must be one printable character'
    endif
    if type(shifted) != v:t_string || strchars(shifted) != 1
      throw 'keyboard_layout_overrides values must be one character'
    endif
    if char2nr(shifted) <= 0x20 || char2nr(shifted) == 0x7f
      throw 'keyboard_layout_overrides values must be printable characters'
    endif
    if has_key(symbols, shifted)
      throw 'keyboard_layout_overrides shifted symbols must be unique'
    endif
    symbols[shifted] = true
    overrides[base] = shifted
  endfor
  return overrides
enddef

def ReadMappings(raw: any): dict<string>
  if type(raw) != v:t_dict
    throw 'mappings must be a dictionary'
  endif
  final actions: dict<string> = {}
  final physical_keys: dict<bool> = {}
  for [key, value] in items(raw)
    if key =~# '^<[0-9A-Za-z_-]\+>$'
      throw 'mapping keys must use Vim keycode expressions: ' .. key
    endif
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
    actions[lhs] = action
  endfor
  return actions
enddef

def ReadDictionaries(raw: any): list<loader.Source>
  if type(raw) != v:t_list
    throw 'dictionaries must be a list'
  endif
  final sources: list<loader.Source> = []
  for source in raw
    var path = ''
    var encoding = 'utf-8'
    if type(source) == v:t_string
      path = source
    elseif type(source) == v:t_dict
      for field in keys(source)
        if index(['path', 'encoding'], field) < 0
          throw 'unknown dictionary source field: ' .. field
        endif
      endfor
      if type(get(source, 'path', v:none)) != v:t_string
        throw 'dictionary source path must be a string'
      endif
      if type(get(source, 'encoding', 'utf-8')) != v:t_string
        throw 'dictionary source encoding must be a string'
      endif
      path = source.path
      encoding = get(source, 'encoding', 'utf-8')
    else
      throw 'dictionary source must be a path string or dictionary'
    endif
    if path == ''
      throw 'dictionary source path must not be empty'
    endif
    if encoding == ''
      throw 'dictionary source encoding must not be empty'
    endif
    sources->add(loader.Source.new(path, encoding))
  endfor
  return sources
enddef

def ReadModePopupLabels(raw: any): dict<string>
  if type(raw) != v:t_dict
    throw 'mode_popup_labels must be a dictionary'
  endif
  final labels = copy(input_mode.DEFAULT_LABELS)
  for [name, value] in items(raw)
    if !has_key(input_mode.LABEL_NAMES, name)
      throw 'unknown mode_popup_labels key: ' .. name
    endif
    if type(value) != v:t_string || value ==# ''
      throw 'mode_popup_labels values must be nonempty strings'
    endif
    labels[name] = value
  endfor
  return labels
enddef

def ReadModePopupMarkers(raw: any): dict<string>
  if type(raw) != v:t_dict
    throw 'mode_popup_markers must be a dictionary'
  endif
  final markers = {modified: '▽', candidate: '▼'}
  for [name, value] in items(raw)
    if index(['modified', 'candidate'], name) < 0
      throw 'unknown mode_popup_markers key: ' .. name
    endif
    if type(value) != v:t_string
      throw 'mode_popup_markers values must be strings'
    endif
    markers[name] = value
  endfor
  return markers
enddef

def Parse(options: dict<any>): Settings
  for section in keys(options)
    if index(['highlight', 'sticky_key', 'keyboard_layout', 'keyboard_layout_overrides', 'mappings', 'dictionaries', 'state_path', 'state_auto',
        'small_tsu_okuri_as_t',
        'registration_prefill', 'registration_auto', 'registration_inline', 'candidate_popup', 'persist_input_mode',
        'mode_popup', 'mode_popup_labels', 'mode_popup_markers', 'mode_popup_time'], section) < 0
      throw 'unknown section: ' .. section
    endif
  endfor
  const highlight = ParseHighlight(ReadHighlight(get(options, 'highlight', {})))
  const sticky_key = ReadStickyKey(get(options, 'sticky_key', ''))
  const keyboard_layout = ReadKeyboardLayout(get(options, 'keyboard_layout', 'US'))
  const keyboard_layout_overrides = ReadKeyboardLayoutOverrides(get(options, 'keyboard_layout_overrides', {}))
  const actions = ReadMappings(get(options, 'mappings', {}))
  if type(get(options, 'persist_input_mode', false)) != v:t_bool
    throw 'persist_input_mode must be a bool'
  endif
  const persist_input_mode: bool = get(options, 'persist_input_mode', false)
  if type(get(options, 'state_path', '')) != v:t_string
    throw 'state_path must be a string'
  endif
  const state_path: string = get(options, 'state_path', '')
  if type(get(options, 'state_auto', false)) != v:t_bool
    throw 'state_auto must be a bool'
  endif
  const state_auto: bool = get(options, 'state_auto', false)
  if state_auto && state_path == ''
    throw 'state_auto requires a nonempty state_path'
  endif
  if type(get(options, 'registration_prefill', true)) != v:t_bool
    throw 'registration_prefill must be a bool'
  endif
  const registration_prefill: bool = get(options, 'registration_prefill', true)
  if type(get(options, 'registration_auto', true)) != v:t_bool
    throw 'registration_auto must be a bool'
  endif
  const registration_auto: bool = get(options, 'registration_auto', true)
  if type(get(options, 'registration_inline', false)) != v:t_bool
    throw 'registration_inline must be a bool'
  endif
  const registration_inline: bool = get(options, 'registration_inline', false)
  if type(get(options, 'candidate_popup', true)) != v:t_bool
    throw 'candidate_popup must be a bool'
  endif
  const candidate_popup: bool = get(options, 'candidate_popup', true)
  if type(get(options, 'mode_popup', true)) != v:t_bool
    throw 'mode_popup must be a bool'
  endif
  const mode_popup: bool = get(options, 'mode_popup', true)
  const mode_popup_labels = ReadModePopupLabels(get(options, 'mode_popup_labels', {}))
  const mode_popup_markers = ReadModePopupMarkers(get(options, 'mode_popup_markers', {}))
  if type(get(options, 'mode_popup_time', 1000)) != v:t_number
      || get(options, 'mode_popup_time', 1000) < 0
    throw 'mode_popup_time must be a nonnegative number'
  endif
  const mode_popup_time: number = get(options, 'mode_popup_time', 1000)
  if type(get(options, 'small_tsu_okuri_as_t', true)) != v:t_bool
    throw 'small_tsu_okuri_as_t must be a bool'
  endif
  const small_tsu_okuri_as_t: bool = get(options, 'small_tsu_okuri_as_t', true)
  const sources = ReadDictionaries(get(options, 'dictionaries', []))
  const entries = loader.Load(sources)
  const destination = state_path == '' ? '' : fnamemodify(state_path, ':p')
  return Settings.new(highlight, Input.new(sticky_key, keyboard_layout, keyboard_layout_overrides,
    actions, entries, small_tsu_okuri_as_t, persist_input_mode), destination, state_auto,
    registration_prefill, registration_auto, registration_inline, candidate_popup, mode_popup, mode_popup_labels,
    mode_popup_markers, mode_popup_time)
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
  return Input.new(current.input.sticky_key, current.input.keyboard_layout,
    current.input.keyboard_layout_overrides, current.input.mappings, current.input.entries,
    current.input.small_tsu_okuri_as_t, current.input.persist_input_mode)
enddef

export def GetStatePath(): string
  return current.state_path
enddef

export def GetStateAuto(): bool
  return current.state_auto
enddef

export def GetRegistrationPrefill(): bool
  return current.registration_prefill
enddef

export def GetRegistrationAuto(): bool
  return current.registration_auto
enddef

export def GetRegistrationInline(): bool
  return current.registration_inline
enddef

export def GetCandidatePopup(): bool
  return current.candidate_popup
enddef

export def GetModePopup(): bool
  return current.mode_popup
enddef

export def GetModePopupLabels(): dict<string>
  return copy(current.mode_popup_labels)
enddef

export def GetModePopupMarkers(): dict<string>
  return copy(current.mode_popup_markers)
enddef

export def GetModePopupTime(): number
  return current.mode_popup_time
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
