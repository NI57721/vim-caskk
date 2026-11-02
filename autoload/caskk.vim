vim9script

import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/scheme/registry.vim' as registry
import autoload 'caskk/binding.vim' as binding

const schemes = registry.Registry.new()

export def RegisterInputScheme(name: string, consonants: dict<string>,
    combinations: dict<string>, specials: list<scheme.SpecialDefinition> = [])
  schemes.Register(name, consonants, combinations, specials)
enddef

export def GetInputScheme(name: string): scheme.CompiledScheme
  return schemes.Get(name)
enddef

export def Enable(name: string)
  binding.Enable(schemes.Get(name))
enddef

export def Disable()
  binding.Disable()
enddef

export def IsEnabled(): bool
  return binding.IsEnabled()
enddef

# Currently the public settings cover highlight.preedit attributes and colors.
export def Config(options: dict<dict<dict<string>>>)
  configuration.Configure(options)
enddef
