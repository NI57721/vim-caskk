vim9script

import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/scheme/roman.vim' as roman
import autoload 'caskk/scheme/azik.vim' as azik

export def BuiltinDefinition(name: string): dict<dict<string>>
  if name ==# 'roman'
    return roman.Definition()
  elseif name ==# 'azik'
    return azik.Definition()
  endif
  throw 'caskk: unknown base input scheme: ' .. name
enddef

# Registration belongs to input grammar, independently of ordinary IME settings.
export class Registry
  var _schemes: dict<scheme.CompiledScheme> = {}

  def new()
    for name in ['roman', 'azik']
      const definition = BuiltinDefinition(name)
      this.Register(name, definition.consonants, definition.combinations,
        scheme.SpecialDefinitions(definition.specials))
    endfor
  enddef

  # Compile before replacement so failed registration leaves the old entry intact.
  # Existing composers retain their compiled scheme when a name is registered again.
  def Register(name: string, consonants: dict<string>, combinations: dict<string>,
      specials: list<scheme.SpecialDefinition> = [], n_fallback: bool = true)
    this._schemes[name] = scheme.Compile(consonants, combinations, specials, n_fallback)
  enddef

  def Get(name: string): scheme.CompiledScheme
    if !has_key(this._schemes, name)
      throw 'caskk: unknown input scheme: ' .. name
    endif
    return this._schemes[name]
  enddef
endclass
