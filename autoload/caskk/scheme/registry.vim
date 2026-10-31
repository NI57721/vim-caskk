vim9script

import autoload 'caskk/scheme.vim' as scheme

# Registration belongs to input grammar, independently of ordinary IME settings.
export class Registry
  var _schemes: dict<scheme.CompiledScheme> = {}

  def new()
  enddef

  # Compile before replacement so failed registration leaves the old entry intact.
  # Existing composers retain their compiled scheme when a name is registered again.
  def Register(name: string, consonants: dict<string>, combinations: dict<string>,
      specials: list<scheme.SpecialDefinition> = [])
    this._schemes[name] = scheme.Compile(consonants, combinations, specials)
  enddef

  def Get(name: string): scheme.CompiledScheme
    if !has_key(this._schemes, name)
      throw 'caskk: unknown input scheme: ' .. name
    endif
    return this._schemes[name]
  enddef
endclass
