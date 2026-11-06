vim9script

import autoload 'caskk/input/mapping.vim' as mapping
import autoload 'caskk/input/mode.vim' as input_mode
import autoload 'caskk/dictionary/loader.vim' as loader
import autoload 'caskk/dictionary/index.vim' as dict_index

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
  const dictionary_index: dict_index.Database
  const small_tsu_okuri_as_t: bool
  const persist_input_mode: bool
  const register_mode_conversions: bool

  def new(this.sticky_key, this.keyboard_layout, keyboard_layout_overrides: dict<string>,
      mappings: dict<string>, dictionary_index: dict_index.Database,
      this.small_tsu_okuri_as_t, this.persist_input_mode, this.register_mode_conversions)
    this.keyboard_layout_overrides = copy(keyboard_layout_overrides)
    this.mappings = copy(mappings)
    this.dictionary_index = dictionary_index
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
  const dictionary_sources: list<loader.Source>

  def new(this.highlight, this.input, this.state_path, this.state_auto, this.registration_prefill,
      this.registration_auto, this.registration_inline, this.candidate_popup, this.mode_popup,
      mode_popup_labels: dict<string>, mode_popup_markers: dict<string>, this.mode_popup_time,
      dictionary_sources: list<loader.Source> = [])
    this.mode_popup_labels = copy(mode_popup_labels)
    this.mode_popup_markers = copy(mode_popup_markers)
    this.dictionary_sources = copy(dictionary_sources)
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

def Parse(options: dict<any>, shared_index: dict_index.Database = null_object): Settings
  for section in keys(options)
    if index(['highlight', 'sticky_key', 'keyboard_layout', 'keyboard_layout_overrides', 'mappings', 'dictionaries', 'state_path', 'state_auto',
        'small_tsu_okuri_as_t',
        'registration_prefill', 'registration_auto', 'registration_inline', 'candidate_popup', 'persist_input_mode',
        'register_mode_conversions',
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
  if type(get(options, 'register_mode_conversions', true)) != v:t_bool
    throw 'register_mode_conversions must be a bool'
  endif
  const register_mode_conversions: bool = get(options, 'register_mode_conversions', true)
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
  if type(get(options, 'mode_popup_time', 0)) != v:t_number
      || get(options, 'mode_popup_time', 0) < 0
    throw 'mode_popup_time must be a nonnegative number'
  endif
  const mode_popup_time: number = get(options, 'mode_popup_time', 0)
  if type(get(options, 'small_tsu_okuri_as_t', true)) != v:t_bool
    throw 'small_tsu_okuri_as_t must be a bool'
  endif
  const small_tsu_okuri_as_t: bool = get(options, 'small_tsu_okuri_as_t', true)
  const sources = ReadDictionaries(get(options, 'dictionaries', []))
  const dictionary_index = shared_index is null_object ? loader.Open(sources) : shared_index
  const destination = state_path == '' ? '' : fnamemodify(state_path, ':p')
  return Settings.new(highlight, Input.new(sticky_key, keyboard_layout, keyboard_layout_overrides,
    actions, dictionary_index, small_tsu_okuri_as_t, persist_input_mode, register_mode_conversions), destination, state_auto,
    registration_prefill, registration_auto, registration_inline, candidate_popup, mode_popup, mode_popup_labels,
    mode_popup_markers, mode_popup_time, sources)
enddef

var current = Parse({})
var shared_dictionary_index = current.input.dictionary_index
var pending_dictionary_builder: loader.DatabaseBuilder = null_object
var dictionary_timer = -1
var dictionary_load_state = 'ready'
var dictionary_load_error = ''
var has_loaded_dictionary = false
var progressive_initial_load = false
var published_dictionary_source_count = 0

const INDEX_LINES_PER_TICK = 1000

def SameDictionaryIndependentSettings(left: Settings, right: Settings): bool
  const a = left.input
  const b = right.input
  return a.sticky_key ==# b.sticky_key
    && a.keyboard_layout ==# b.keyboard_layout
    && a.keyboard_layout_overrides == b.keyboard_layout_overrides
    && a.mappings == b.mappings
    && a.small_tsu_okuri_as_t == b.small_tsu_okuri_as_t
    && a.persist_input_mode == b.persist_input_mode
    && a.register_mode_conversions == b.register_mode_conversions
    && left.registration_auto == right.registration_auto
    && left.registration_prefill == right.registration_prefill
    && left.registration_inline == right.registration_inline
    && left.state_path ==# right.state_path
    && left.state_auto == right.state_auto
    && left.candidate_popup == right.candidate_popup
    && left.mode_popup == right.mode_popup
    && left.mode_popup_labels == right.mode_popup_labels
    && left.mode_popup_markers == right.mode_popup_markers
    && left.mode_popup_time == right.mode_popup_time
enddef

def AdvanceDictionaryLoad(timer: number)
  if timer != dictionary_timer || pending_dictionary_builder is null_object
    return
  endif
  try
    const done = pending_dictionary_builder.Step(INDEX_LINES_PER_TICK)
    const completed_sources = pending_dictionary_builder.CompletedSourceCount()
    if progressive_initial_load && completed_sources > published_dictionary_source_count
      shared_dictionary_index.ReplacePartialWith(pending_dictionary_builder.CompletedResult())
      published_dictionary_source_count = completed_sources
    endif
    if done
      shared_dictionary_index.ReplaceWith(pending_dictionary_builder.Result())
      has_loaded_dictionary = true
      pending_dictionary_builder = null_object
      dictionary_timer = -1
      dictionary_load_state = 'ready'
      dictionary_load_error = ''
      return
    endif
    dictionary_timer = timer_start(0, AdvanceDictionaryLoad)
  catch
    dictionary_load_error = v:exception
    if progressive_initial_load
      shared_dictionary_index.MarkReady()
      has_loaded_dictionary = shared_dictionary_index.SourceCount() > 0
    endif
    pending_dictionary_builder = null_object
    dictionary_timer = -1
    dictionary_load_state = 'error'
    echohl ErrorMsg
    echomsg 'Caskk: dictionary reload failed; keeping the previous dictionary: ' .. dictionary_load_error
    echohl None
  endtry
enddef

export def DictionaryLoadStatus(): dict<string>
  return {state: dictionary_load_state, error: dictionary_load_error}
enddef

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
    current.input.keyboard_layout_overrides, current.input.mappings, current.input.dictionary_index,
    current.input.small_tsu_okuri_as_t, current.input.persist_input_mode,
    current.input.register_mode_conversions)
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
    parsed = Parse(options, shared_dictionary_index)
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
  try
    shared_dictionary_index.ReplaceWith(loader.Open(parsed.dictionary_sources))
  catch
    const reason = v:exception
    hlset([{name: GROUP, cleared: true}])
    hlset(previous)
    throw 'caskk: invalid configuration: ' .. reason
  endtry
  if dictionary_timer >= 0
    timer_stop(dictionary_timer)
    dictionary_timer = -1
  endif
  pending_dictionary_builder = null_object
  current = parsed
  has_loaded_dictionary = !empty(parsed.dictionary_sources)
  dictionary_load_state = 'ready'
  dictionary_load_error = ''
enddef

def NeedsIncrementalLoad(sources: list<loader.Source>): bool
  var total_size = 0
  for source in sources
    const size = getfsize(source.path)
    if size < 0
      return false
    endif
    total_size += size
    if total_size >= 131072
      return true
    endif
  endfor
  return false
enddef

export def ConfigureIncrementally(options: dict<any>): bool
  var parsed: Settings
  try
    parsed = Parse(options, shared_dictionary_index)
  catch
    const reason = v:exception
    if stridx(reason, 'caskk: invalid configuration:') == 0
      throw reason
    endif
    throw 'caskk: invalid configuration: ' .. reason
  endtry

  if !NeedsIncrementalLoad(parsed.dictionary_sources)
    const reset_bindings = !SameDictionaryIndependentSettings(current, parsed)
    Configure(options)
    return reset_bindings
  endif

  const reset_bindings = !SameDictionaryIndependentSettings(current, parsed)
  const previous = hlget(GROUP)
  try
    Install(parsed.highlight)
  catch
    const reason = v:exception
    hlset([{name: GROUP, cleared: true}])
    hlset(previous)
    throw 'caskk: invalid configuration: ' .. reason
  endtry

  if dictionary_timer >= 0
    timer_stop(dictionary_timer)
    dictionary_timer = -1
  endif
  dictionary_load_error = ''
  progressive_initial_load = !has_loaded_dictionary
  published_dictionary_source_count = 0
  if progressive_initial_load
    shared_dictionary_index.ResetForLoading()
  endif
  pending_dictionary_builder = loader.DatabaseBuilder.new(parsed.dictionary_sources)
  current = parsed
  dictionary_load_state = 'loading'
  if pending_dictionary_builder.IsDone()
    shared_dictionary_index.ReplaceWith(pending_dictionary_builder.Result())
    pending_dictionary_builder = null_object
    dictionary_load_state = 'ready'
    has_loaded_dictionary = !empty(parsed.dictionary_sources)
  else
    dictionary_timer = timer_start(0, AdvanceDictionaryLoad)
  endif
  return reset_bindings
enddef

augroup caskk_highlight
  autocmd!
  autocmd ColorScheme * ApplyHighlight()
augroup END
