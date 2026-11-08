vim9script

import 'caskk/input.vim' as input
import autoload 'caskk/input/layout.vim' as layout

# Input is one physical KeyToken at a time, already named by the integration layer.
# An empty sticky_key disables sticky input.
export class Normalizer
  const _sticky_key: string = ''
  const _keyboard_layout: string = ''
  const _keyboard_layout_overrides: dict<string>
  var _modified: bool = false

  def new(this._sticky_key = v:none, this._keyboard_layout = v:none,
      keyboard_layout_overrides: dict<string> = {})
    this._keyboard_layout_overrides = copy(keyboard_layout_overrides)
  enddef

  # Inspect layout normalization without consuming a pending sticky modifier.
  def NormalizeKey(key: string): input.Event
    return layout.Normalize(this._keyboard_layout, key, this._keyboard_layout_overrides)
  enddef

  def Feed(key: string): list<input.Event>
    if this._sticky_key != '' && key == this._sticky_key
      this._modified = true
      return []
    endif

    const shifted = this.NormalizeKey(key)
    const uppercase = key =~# '^[A-Z]$'
    const event = input.Event.new(uppercase ? tolower(key) : shifted.key,
      this._modified || uppercase || shifted.modified)
    this._modified = false
    return [event]
  enddef

  # Explicit special keys keep their physical token, while a pending sticky
  # modifier still applies to that token.
  def FeedSpecial(key: string): list<input.Event>
    if this._sticky_key != '' && key == this._sticky_key
      this._modified = true
      return []
    endif
    const event = input.Event.new(key, this._modified)
    this._modified = false
    return [event]
  enddef

  def Backspace(): bool
    const pending = this._modified
    this._modified = false
    return pending
  enddef

  def RestoreModifier()
    this._modified = true
  enddef

  def HasPendingModifier(): bool
    return this._modified
  enddef

  # Shifted punctuation is ordinary Direct input until a composition context
  # gives its normalized key a Japanese-input meaning.
  def IsShiftedSymbol(key: string): bool
    return key !=# this._sticky_key && key !~# '^[A-Z]$' && layout.Normalize(this._keyboard_layout, key,
      this._keyboard_layout_overrides).modified
  enddef

  # Clear unfinished sticky input when the input session ends or is cancelled.
  def Reset()
    this._modified = false
  enddef
endclass
