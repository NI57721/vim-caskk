vim9script

import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/scheme/registry.vim' as registry
import autoload 'caskk/binding.vim' as binding
import autoload 'caskk/commandline.vim' as commandline
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/dictionary/export.vim' as dictionary_export
import 'caskk/registration.vim' as registration

const schemes = registry.Registry.new()

def ReadSchemeMap(definition: dict<any>, field: string,
    defaults: dict<string> = {}, inherit: bool = false): dict<string>
  if inherit && !has_key(definition, field)
    return copy(defaults)
  endif
  if !has_key(definition, field) || type(definition[field]) != v:t_dict
    throw 'caskk: invalid input scheme: ' .. field .. ' must be a dictionary'
  endif
  final values: dict<string> = copy(defaults)
  final overridden: dict<bool> = {}
  for [key, raw_value] in items(definition[field])
    if inherit
      const sequence = json_encode(scheme.InputKeys(key))
      if has_key(overridden, sequence)
        throw 'caskk: invalid input scheme: duplicate normalized ' .. field .. ' key'
      endif
      overridden[sequence] = true
      for existing in keys(values)
        if json_encode(scheme.InputKeys(existing)) ==# sequence
          remove(values, existing)
        endif
      endfor
      if type(raw_value) == v:t_none && string(raw_value) ==# string(v:null)
        continue
      endif
    endif
    if type(raw_value) != v:t_string
      throw 'caskk: invalid input scheme: ' .. field .. ' values must be strings'
    endif
    const value: string = raw_value
    values[key] = value
  endfor
  return values
enddef

export def RegisterInputScheme(definition: dict<any>)
  for field in keys(definition)
    if index(['name', 'base', 'consonants', 'combinations', 'specials', 'n_fallback'], field) < 0
      throw 'caskk: invalid input scheme: unknown field: ' .. field
    endif
  endfor
  if !has_key(definition, 'name') || type(definition.name) != v:t_string
    throw 'caskk: invalid input scheme: name must be a string'
  endif
  const fallback = get(definition, 'n_fallback', true)
  if type(fallback) != v:t_bool
    throw 'caskk: invalid input scheme: n_fallback must be a boolean'
  endif
  const n_fallback: bool = fallback
  const name: string = definition.name
  const inherit = has_key(definition, 'base')
  final defaults: dict<dict<string>> = {consonants: {}, combinations: {}, specials: {}}
  if inherit
    if type(definition.base) != v:t_string
      throw 'caskk: invalid input scheme: base must be a string'
    endif
    extend(defaults, registry.BuiltinDefinition(definition.base), 'force')
  endif
  const consonants = scheme.ValidateConsonants(
    ReadSchemeMap(definition, 'consonants', defaults.consonants, inherit))
  const combinations = scheme.ValidateCombinations(
    ReadSchemeMap(definition, 'combinations', defaults.combinations, inherit))
  const specials = inherit || has_key(definition, 'specials')
    ? ReadSchemeMap(definition, 'specials', defaults.specials, inherit) : {}
  schemes.Register(name, consonants, combinations, scheme.SpecialDefinitions(specials), n_fallback)
  commandline.Disable()
  binding.DisableAll()
enddef

export def GetInputScheme(name: string): scheme.CompiledScheme
  return schemes.Get(name)
enddef

def InitializeAutomaticState()
  if configuration.GetStateAuto()
    user_runtime.InitializeAutomatic(configuration.GetStatePath())
  endif
enddef

export def Enable(name: string)
  const compiled = schemes.Get(name)
  if commandline.IsTarget()
    InitializeAutomaticState()
    commandline.Enable(compiled)
    return
  elseif getcmdtype() != '' || getcmdwintype() != ''
    return
  endif
  if binding.IsEnabled()
    return
  endif
  const input = configuration.GetInput()
  binding.Enable(InitializeAutomaticState, compiled, input.sticky_key, input.mappings, {}, user_runtime.Get(),
    configuration.GetRegistrationAuto(), input.small_tsu_okuri_as_t, input.keyboard_layout,
    input.keyboard_layout_overrides, input.persist_input_mode, input.register_mode_conversions,
    input.dictionary_index, input.keep_preedit_on_backspace, input.affix_key)
enddef

export def Disable()
  if getcmdtype() != ''
    if commandline.IsTarget()
      commandline.Disable()
    endif
    return
  endif
  binding.Disable()
enddef

export def Toggle(name: string)
  if IsEnabled()
    Disable()
  else
    Enable(name)
  endif
enddef

export def IsEnabled(): bool
  return getcmdtype() != '' ? commandline.IsEnabled() : binding.IsEnabled()
enddef

export def GetRegistrationRequest(): registration.Request
  return binding.GetRegistrationRequest()
enddef

export def OpenRegistration()
  binding.OpenRegistration(configuration.GetRegistrationPrefill())
enddef

export def Reconvert(): bool
  return binding.Reconvert()
enddef

export def CompleteRegistration(text: string, annotations: list<string> = [])
  binding.CompleteRegistration(text, annotations)
enddef

export def CancelRegistration()
  binding.CancelRegistration()
enddef

export def LoadState()
  user_runtime.Load(configuration.GetStatePath())
enddef

export def SaveState()
  user_runtime.Save(configuration.GetStatePath())
enddef

export def ExportUserDictionary(path: string)
  dictionary_export.Write(path, user_runtime.Get().GetSnapshot())
enddef

# The heterogeneous user dictionary is validated at the configuration boundary.
export def Config(options: dict<any>)
  if configuration.ConfigureIncrementally(options)
    commandline.Disable()
    binding.DisableAll()
  endif
enddef

export def GetDictionaryLoadStatus(): dict<string>
  return configuration.DictionaryLoadStatus()
enddef

def SaveAutomaticState()
  if configuration.GetStateAuto()
    user_runtime.SaveAutomatic(configuration.GetStatePath())
  endif
enddef

def ReloadWrittenState(path: string)
  if configuration.GetStateAuto() && fnamemodify(path, ':p') ==# configuration.GetStatePath()
    try
      user_runtime.Load(configuration.GetStatePath())
    catch
      echohl ErrorMsg
      echomsg v:exception
      echohl None
    endtry
  endif
enddef

augroup caskk_user_state
  autocmd!
  autocmd VimLeavePre * SaveAutomaticState()
  autocmd BufWritePost * ReloadWrittenState(expand('<afile>:p'))
augroup END
