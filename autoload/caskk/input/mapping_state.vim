vim9script

# Preserve raw keycodes and the defining script context in typed fields.
class Mapping
  const text: dict<string>
  const numbers: dict<number>
  const alternate: dict<string>

  def new(lhs: string, mode: string = 'i')
    const native = maparg(lhs, mode, false, true)
    final text: dict<string> = {}
    for name in ['lhs', 'lhsraw', 'rhs', 'mode']
      text[name] = get(native, name, name ==# 'mode' ? mode : '')
    endfor
    final numbers: dict<number> = {}
    for name in ['silent', 'noremap', 'script', 'expr', 'buffer', 'sid', 'scriptversion', 'lnum', 'nowait']
      numbers[name] = get(native, name, 0)
    endfor
    this.text = text
    this.numbers = numbers
    this.alternate = has_key(native, 'lhsrawalt') ? {lhsrawalt: native.lhsrawalt} : {}
  enddef

  def MatchesCurrent(lhs: string): bool
    const other = Mapping.new(lhs, this.text.mode)
    return this.text ==# other.text && this.numbers == other.numbers && this.alternate ==# other.alternate
  enddef

  def Restore()
    if !this.numbers.buffer
      return
    endif
    # Heterogeneous native mapping data stays at the mapset() boundary.
    mapset(this.text.mode, false, extend({
      lhs: this.text.lhs, lhsraw: this.text.lhsraw, rhs: this.text.rhs,
      silent: this.numbers.silent, noremap: this.numbers.noremap,
      script: this.numbers.script, expr: this.numbers.expr,
      buffer: this.numbers.buffer, sid: this.numbers.sid,
      scriptversion: this.numbers.scriptversion, lnum: this.numbers.lnum,
      nowait: this.numbers.nowait,
    }, this.alternate))
  enddef
endclass

export class State
  var _saved: dict<Mapping> = {}
  var _installed: dict<Mapping> = {}

  def new()
  enddef

  def Has(lhs: string): bool
    return has_key(this._installed, lhs)
  enddef

  def Owns(lhs: string): bool
    for installed in values(this._installed)
      if installed.MatchesCurrent(lhs)
        return true
      endif
    endfor
    return false
  enddef

  def Install(lhs: string, rhs: string)
    this._saved[lhs] = Mapping.new(lhs)
    this.Reinstall(lhs, rhs)
  enddef

  def Reinstall(lhs: string, rhs: string)
    execute 'inoremap <buffer> <silent> ' .. lhs .. ' ' .. rhs
    this._installed[lhs] = Mapping.new(lhs)
  enddef

  def Release(lhs: string)
    execute 'silent! iunmap <buffer> ' .. lhs
    this._saved[lhs].Restore()
  enddef

  def RestoreKey(lhs: string)
    if !this.Has(lhs)
      return
    endif
    if this._installed[lhs].MatchesCurrent(lhs)
      this.Release(lhs)
    endif
    remove(this._installed, lhs)
    remove(this._saved, lhs)
  enddef

  def Restore()
    for lhs in keys(this._installed)
      this.RestoreKey(lhs)
    endfor
  enddef

  def InheritSaved(other: State)
    for lhs in keys(this._installed)
      if has_key(other._saved, lhs)
        this._saved[lhs] = other._saved[lhs]
      endif
    endfor
  enddef

  def Forget()
    this._installed = {}
    this._saved = {}
  enddef
endclass
