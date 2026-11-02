vim9script

import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/scheme/registry.vim' as registry
import autoload 'caskk/binding.vim' as binding
import autoload 'caskk/user_state/runtime.vim' as user_runtime

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
  const input = configuration.GetInput()
  binding.Enable(compiled, input.sticky_key, input.mappings, input.entries, user_runtime.Get())
enddef

export def Disable()
  binding.Disable()
enddef

export def IsEnabled(): bool
  return binding.IsEnabled()
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
