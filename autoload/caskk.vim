vim9script

import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/scheme/registry.vim' as registry
import autoload 'caskk/binding.vim' as binding
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/dictionary/export.vim' as dictionary_export
import 'caskk/registration.vim' as registration

const schemes = registry.Registry.new()

def ReadSchemeMap(definition: dict<any>, field: string): dict<string>
  if !has_key(definition, field) || type(definition[field]) != v:t_dict
    throw 'caskk: invalid input scheme: ' .. field .. ' must be a dictionary'
  endif
  final values: dict<string> = {}
  for [key, raw_value] in items(definition[field])
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
    if index(['name', 'consonants', 'combinations', 'specials'], field) < 0
      throw 'caskk: invalid input scheme: unknown field: ' .. field
    endif
  endfor
  if !has_key(definition, 'name') || type(definition.name) != v:t_string
    throw 'caskk: invalid input scheme: name must be a string'
  endif
  const name: string = definition.name
  const consonants = scheme.ValidateConsonants(ReadSchemeMap(definition, 'consonants'))
  const combinations = scheme.ValidateCombinations(ReadSchemeMap(definition, 'combinations'))
  final specials: dict<string> = has_key(definition, 'specials')
    ? ReadSchemeMap(definition, 'specials') : {}
  schemes.Register(name, consonants, combinations, scheme.SpecialDefinitions(specials))
  binding.DisableAll()
enddef

export def GetInputScheme(name: string): scheme.CompiledScheme
  return schemes.Get(name)
enddef

export def Enable(name: string)
  const compiled = schemes.Get(name)
  if binding.IsEnabled()
    return
  endif
  const input = configuration.GetInput()
  binding.Enable(compiled, input.sticky_key, input.mappings, {}, user_runtime.Get(),
    configuration.GetRegistrationAuto(), input.small_tsu_okuri_as_t, input.keyboard_layout,
    input.keyboard_layout_overrides, input.persist_input_mode, input.register_mode_conversions,
    input.dictionary_index)
  try
    if configuration.GetStateAuto()
      user_runtime.InitializeAutomatic(configuration.GetStatePath())
    endif
  catch
    const reason = v:exception
    binding.Disable()
    throw reason
  endtry
enddef

export def Disable()
  binding.Disable()
enddef

export def Toggle(name: string)
  if binding.IsEnabled()
    binding.Disable()
  else
    Enable(name)
  endif
enddef

export def IsEnabled(): bool
  return binding.IsEnabled()
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

augroup caskk_user_state
  autocmd!
  autocmd VimLeavePre * SaveAutomaticState()
augroup END
