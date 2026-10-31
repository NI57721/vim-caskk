vim9script

import 'caskk/composition.vim' as composition

# Values captured after one output, independent of later state changes.
export class Snapshot
  const in_preedit: bool
  const reading: string
  const okuri: string
  const okuri_started: bool

  def new(this.in_preedit, this.reading, this.okuri, this.okuri_started)
  enddef
endclass

# Reading state only; committed text is returned to the caller, not retained.
export class State
  var in_preedit: bool = false
  var reading: string = ''
  var okuri: string = ''
  var okuri_started: bool = false

  def new()
  enddef

  def GetSnapshot(): Snapshot
    return Snapshot.new(this.in_preedit, this.reading, this.okuri, this.okuri_started)
  enddef

  # Interpret each result in order, using the state left by the preceding result.
  # Direct output is returned immediately. Preedit output is retained here.
  def Apply(composed: composition.Result): string
    if composed.start_conversion
      this.in_preedit = true
    endif
    if !this.in_preedit
      return composed.reading .. composed.okuri
    endif

    if this.okuri_started
      this.okuri ..= composed.reading .. composed.okuri
    else
      this.reading ..= composed.reading
      this.okuri ..= composed.okuri
      this.okuri_started = composed.okuri_started
    endif
    return ''
  enddef

  def Commit(): string
    const text = this.reading .. this.okuri
    this.in_preedit = false
    this.reading = ''
    this.okuri = ''
    this.okuri_started = false
    return text
  enddef
endclass
