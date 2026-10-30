vim9script

import 'caskk/input.vim' as input

# Input is one physical KeyToken at a time, already named by the integration layer.
# An empty sticky_key disables sticky input. No layout-specific symbol mapping is done.
export class Normalizer
  const _sticky_key: string = ''
  var _modified: bool = false

  def new(this._sticky_key = v:none)
  enddef

  def Feed(key: string): list<input.Event>
    if !this._modified && this._sticky_key != '' && key == this._sticky_key
      this._modified = true
      return []
    endif

    const uppercase = key =~# '^[A-Z]$'
    const event = input.Event.new(uppercase ? tolower(key) : key, this._modified || uppercase)
    this._modified = false
    return [event]
  enddef

  # Clear unfinished sticky input when the input session ends or is cancelled.
  def Reset()
    this._modified = false
  enddef
endclass
