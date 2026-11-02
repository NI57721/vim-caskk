vim9script

import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/scheme/registry.vim' as registry
import autoload 'caskk/binding.vim' as binding
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import 'caskk/registration.vim' as registration

const schemes = registry.Registry.new()

export def RegisterInputScheme(name: string, consonants: dict<string>,
    combinations: dict<string>, specials: list<scheme.SpecialDefinition> = [])
  schemes.Register(name, consonants, combinations, specials)
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
  binding.Enable(compiled, input.sticky_key, input.mappings, input.entries, user_runtime.Get())
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

export def IsEnabled(): bool
  return binding.IsEnabled()
enddef

export def GetRegistrationRequest(): registration.Request
  return binding.GetRegistrationRequest()
enddef

export def OpenRegistration()
  binding.OpenRegistration(configuration.GetRegistrationPrefill())
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

# The heterogeneous user dictionary is validated at the configuration boundary.
export def Config(options: dict<any>)
  configuration.Configure(options)
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
