vim9script

import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/insert.vim' as insert
import autoload 'caskk/session.vim' as session
import autoload 'caskk/user_state.vim' as user_state
import 'caskk/dictionary.vim' as dictionary

const ACTIONS = ['StartConversion', 'NextCandidate', 'PreviousCandidate', 'Commit']

def Lhs(token: string): string
  if token == ' '
    return '<Space>'
  elseif token == '|'
    return '<Bar>'
  elseif token == '\'
    return '<Bslash>'
  elseif token == '<'
    return '<lt>'
  elseif token =~# '^<[0-9A-Za-z_-]\+>$'
    return token
  elseif strchars(token) == 1 && char2nr(token) >= 0x21
    return token
  endif
  throw 'caskk: unsupported mapping KeyToken: ' .. token
enddef

# Preserve raw keycodes and the defining script context in typed fields.
class Mapping
  const text: dict<string>
  const numbers: dict<number>
  const alternate: dict<string>

  def new(lhs: string)
    const native = maparg(lhs, 'i', false, true)
    final text: dict<string> = {}
    for name in ['lhs', 'lhsraw', 'rhs', 'mode']
      text[name] = get(native, name, '')
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
    const other = Mapping.new(lhs)
    return this.text ==# other.text && this.numbers == other.numbers && this.alternate ==# other.alternate
  enddef

  def Restore()
    if !this.numbers.buffer
      return
    endif
    # Heterogeneous native mapping data stays at the mapset() boundary.
    mapset('i', false, extend({
      lhs: this.text.lhs, lhsraw: this.text.lhsraw, rhs: this.text.rhs,
      silent: this.numbers.silent, noremap: this.numbers.noremap,
      script: this.numbers.script, expr: this.numbers.expr,
      buffer: this.numbers.buffer, sid: this.numbers.sid,
      scriptversion: this.numbers.scriptversion, lnum: this.numbers.lnum,
      nowait: this.numbers.nowait,
    }, this.alternate))
  enddef
endclass

export class Binding
  const _buffer: number
  const _compiled: scheme.CompiledScheme
  const _sticky: string
  const _entries: dict<dictionary.Entry>
  const _preferences: user_state.State
  const _actions: dict<string>
  const _keys: dict<string>
  var _saved: dict<Mapping> = {}
  var _installed: dict<Mapping> = {}
  var _editor: insert.Editor = null_object
  var _last: list<session.Result> = []
  var _enabled: bool = false

  def new(compiled: scheme.CompiledScheme, sticky_key: string = '',
      entries: dict<dictionary.Entry> = {}, preferences: user_state.State = null_object,
      actions: dict<string> = {})
    this._buffer = bufnr('%')
    this._compiled = compiled
    this._sticky = sticky_key
    this._entries = copy(entries)
    this._preferences = preferences is null_object ? user_state.State.new() : preferences
    this._actions = copy(actions)
    final tokens: dict<bool> = {}
    for key in keys(compiled.table.consonants) + keys(compiled.table.combinations)
      tokens[key] = true
    endfor
    for rule in compiled.specials
      for key in rule.keys
        tokens[key] = true
      endfor
    endfor
    for key in keys(tokens)
      if key =~# '^[a-z]$'
        tokens[toupper(key)] = true
      endif
    endfor
    if sticky_key != ''
      tokens[sticky_key] = true
    endif
    for [key, action] in items(actions)
      if index(ACTIONS, action) < 0
        throw 'caskk: unknown binding action: ' .. action
      endif
      tokens[key] = true
    endfor
    final lhs: dict<string> = {}
    for key in keys(tokens)
      lhs[key] = Lhs(key)
    endfor
    this._keys = lhs
  enddef

  def _CheckTarget()
    if bufnr('%') != this._buffer
      throw 'caskk: binding target must be the current buffer'
    endif
  enddef

  def _Restore()
    for [key, installed] in items(this._installed)
      if installed.MatchesCurrent(this._keys[key])
        execute 'silent! iunmap <buffer> ' .. this._keys[key]
        this._saved[key].Restore()
      endif
    endfor
    this._installed = {}
    this._saved = {}
  enddef

  def Enable()
    this._CheckTarget()
    if this._enabled
      return
    endif
    const id = string(this._buffer)
    if has_key(bindings, id)
      throw 'caskk: current buffer already has an IME binding'
    endif
    try
      for key in sort(keys(this._keys))
        const lhs = this._keys[key]
        for installed in values(this._installed)
          if installed.MatchesCurrent(lhs)
            throw 'caskk: duplicate physical mapping: ' .. key
          endif
        endfor
        this._saved[key] = Mapping.new(lhs)
        var argument = substitute(string(key), '<', '<lt>', 'g')
        argument = substitute(argument, '\\', '<Bslash>', 'g')
        argument = substitute(argument, '|', '<Bar>', 'g')
        execute 'inoremap <buffer> <silent> ' .. lhs .. ' <ScriptCmd>Dispatch(' .. this._buffer .. ', ' .. argument .. ')<CR>'
        this._installed[key] = Mapping.new(lhs)
      endfor
      bindings[id] = this
      this._enabled = true
      execute 'autocmd caskk_input InsertLeave,BufLeave,WinLeave <buffer=' .. this._buffer .. '> Leave(' .. this._buffer .. ')'
      execute 'autocmd caskk_input BufWipeout <buffer=' .. this._buffer .. '> Forget(' .. this._buffer .. ')'
      if mode(1) =~# '^i'
        this.Enter()
      endif
    catch
      const reason = v:exception
      execute 'autocmd! caskk_input * <buffer=' .. this._buffer .. '>'
      this._Restore()
      if has_key(bindings, id)
        remove(bindings, id)
      endif
      this._enabled = false
      throw reason
    endtry
  enddef

  def Disable()
    if !this._enabled
      return
    endif
    this._CheckTarget()
    try
      this.Leave()
    finally
      execute 'autocmd! caskk_input * <buffer=' .. this._buffer .. '>'
      this._Restore()
      remove(bindings, string(this._buffer))
      this._enabled = false
    endtry
  enddef

  def _Record(results: list<session.Result>)
    this._last = copy(results)
    for result in results
      if !empty(result.unhandled)
        throw 'caskk: native handling of unhandled input is not connected'
      endif
    endfor
  enddef

  def Enter()
    this._CheckTarget()
    this._editor = insert.Editor.new(this._compiled, this._sticky, this._entries, this._preferences)
  enddef

  def Leave()
    if this._editor is null_object
      return
    endif
    try
      this._Record(this._editor.Close())
    finally
      this._editor = null_object
    endtry
  enddef

  def Dispatch(key: string)
    this._CheckTarget()
    if this._editor is null_object
      this.Enter()
    endif
    const action = get(this._actions, key, '')
    if action ==# 'StartConversion'
      this._Record(this._editor.StartConversion())
    elseif action ==# 'NextCandidate'
      this._Record([this._editor.NextCandidate()])
    elseif action ==# 'PreviousCandidate'
      this._Record([this._editor.PreviousCandidate()])
    elseif action ==# 'Commit'
      this._Record(this._editor.Commit())
    else
      this._Record(this._editor.Feed(key))
    endif
  enddef

  def Forget()
    if this._enabled
      remove(bindings, string(this._buffer))
    endif
    this._editor = null_object
    this._installed = {}
    this._saved = {}
    this._enabled = false
  enddef

  def IsEnabled(): bool
    return this._enabled
  enddef

  def GetEditor(): insert.Editor
    return this._editor
  enddef

  def GetLastResults(): list<session.Result>
    return copy(this._last)
  enddef
endclass

var bindings: dict<Binding> = {}

def Leave(number: number)
  if has_key(bindings, string(number))
    bindings[string(number)].Leave()
  endif
enddef

def Forget(number: number)
  if has_key(bindings, string(number))
    bindings[string(number)].Forget()
  endif
enddef

def Dispatch(number: number, key: string)
  if has_key(bindings, string(number))
    bindings[string(number)].Dispatch(key)
  endif
enddef

augroup caskk_input
augroup END
