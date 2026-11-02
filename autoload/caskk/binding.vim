vim9script

import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/insert.vim' as insert
import autoload 'caskk/session.vim' as session
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/input/keycode.vim' as keycode
import autoload 'caskk/input/mapping.vim' as mapping
import 'caskk/dictionary.vim' as dictionary
import 'caskk/registration.vim' as registration

const NATIVE_KEYS = ['<Left>', '<Right>', '<Up>', '<Down>', '<Home>', '<End>', '<CR>', '<BS>']

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
  const _native: dict<bool>
  var _saved: dict<Mapping> = {}
  var _installed: dict<Mapping> = {}
  var _editor: insert.Editor = null_object
  var _last: list<session.Result> = []
  var _enabled: bool = false
  var _registration_reply: dictionary.Candidate = null_object
  var _registration_ticket: number = 0

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
      mapping.ValidateAction(action)
      tokens[key] = true
    endfor
    final lhs: dict<string> = {}
    for key in keys(tokens)
      lhs[key] = mapping.Lhs(key)
    endfor
    # Capture ordinary punctuation and letters too, so native insertion does
    # not bypass an active Preedit. Explicit named aliases keep precedence.
    for code in range(0x20, 0x7e)
      const key = nr2char(code)
      const physical = mapping.Lhs(key)
      if !has_key(lhs, key) && index(values(lhs), physical) < 0
        lhs[key] = physical
      endif
    endfor
    final native: dict<bool> = {}
    for key in NATIVE_KEYS
      const physical = mapping.Lhs(key)
      if index(values(lhs), physical) < 0
        lhs[key] = physical
        native[key] = true
      endif
    endfor
    this._keys = lhs
    this._native = native
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
      execute 'autocmd caskk_input InsertCharPre <buffer=' .. this._buffer .. '> BeforeCharacter(' .. this._buffer .. ')'
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
      this.Leave(true)
    finally
      this._ClearRegistrationReply()
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
    if this._editor isnot null_object && this._editor.IsRegistrationSuspended()
      throw 'caskk: input is suspended for dictionary registration'
    endif
    this._editor = insert.Editor.new(this._compiled, this._sticky, this._entries, this._preferences)
  enddef

  def Leave(force: bool = false)
    if this._editor is null_object
      return
    endif
    if !force && this._editor.IsRegistrationSuspended()
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
    if this._editor isnot null_object && this._editor.IsRegistrationSuspended()
      throw 'caskk: input is suspended for dictionary registration'
    endif
    if has_key(this._native, key)
      if key ==# '<BS>' && this._editor isnot null_object && this._editor.BackspacePending()
        this._last = []
        return
      endif
      # End the IME transaction before native motion or editing. Replay ahead
      # of later input without remapping back into this binding.
      this.Leave()
      feedkeys(keycode.Encode(key), 'in')
      return
    endif
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
    this._ClearRegistrationReply()
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

  def GetRegistrationRequest(): registration.Request
    if this._editor is null_object
      return null_object
    endif
    const request = this._editor.GetRegistrationRequest()
    if request is null_object
      return null_object
    endif
    return registration.Request.new(request.query.reading, request.okuri,
      request.query.exact_okuri, request.query.lookup_key)
  enddef

  def CompleteRegistration(text: string, annotations: list<string> = [])
    this._CheckTarget()
    if this._editor is null_object
      throw 'caskk: no current dictionary registration request'
    endif
    this._Record([this._editor.Register(dictionary.Candidate.new(text, annotations))])
  enddef

  def SuspendRegistration()
    this._CheckTarget()
    if this._editor is null_object
      throw 'caskk: no current dictionary registration request'
    endif
    this._editor.SuspendRegistration()
  enddef

  def ResumeRegistration()
    this._CheckTarget()
    if this._editor is null_object
      throw 'caskk: no suspended dictionary registration'
    endif
    this._editor.ResumeRegistration()
  enddef

  def _ClearRegistrationReply()
    this._registration_reply = null_object
    this._registration_ticket = 0
  enddef

  # A null candidate cancels registration. User text never enters the key queue.
  def QueueRegistrationResult(candidate: dictionary.Candidate = null_object)
    this._CheckTarget()
    if this._registration_ticket != 0
      throw 'caskk: registration result is already queued'
    endif
    if this._editor is null_object
      throw 'caskk: no suspended dictionary registration'
    endif
    if candidate isnot null_object && candidate.text == ''
      throw 'caskk: registered candidate text must not be empty'
    endif
    this._editor.PrepareRegistrationResume()
    this._registration_reply = candidate is null_object ? null_object
      : dictionary.Candidate.new(candidate.text, candidate.annotations)
    next_registration_ticket += 1
    this._registration_ticket = next_registration_ticket
    feedkeys("\<Cmd>call caskk#binding#ResumeRegistrationResult(" .. this._buffer
      .. ', ' .. this._registration_ticket .. ")\<CR>", 'in')
  enddef

  def ResumeQueuedRegistration(ticket: number)
    if ticket == 0 || ticket != this._registration_ticket
      return
    endif
    try
      if this._editor is null_object
        throw 'caskk: no suspended dictionary registration'
      endif
      const prefix = this._editor.PrepareRegistrationResume()
      if prefix == ''
        this.ApplyQueuedRegistration(ticket)
      else
        feedkeys(prefix .. "\<Cmd>call caskk#binding#ApplyRegistrationResult(" .. this._buffer
          .. ', ' .. ticket .. ")\<CR>", 'in')
      endif
    catch
      const reason = v:exception
      this._ClearRegistrationReply()
      throw reason
    endtry
  enddef

  def ApplyQueuedRegistration(ticket: number)
    if ticket == 0 || ticket != this._registration_ticket
      return
    endif
    const candidate = this._registration_reply
    try
      this.ResumeRegistration()
      if candidate is null_object
        this.CancelRegistration()
      else
        this.CompleteRegistration(candidate.text, candidate.annotations)
      endif
    finally
      this._ClearRegistrationReply()
    endtry
  enddef

  def CancelRegistration()
    this._CheckTarget()
    if this._editor is null_object
      throw 'caskk: no current dictionary registration request'
    endif
    this._Record([this._editor.CancelRegistration()])
  enddef
endclass

var bindings: dict<Binding> = {}
var next_registration_ticket: number = 0

# Queued commands carry only the target buffer and this reply's generation.
export def ResumeRegistrationResult(number: number, ticket: number)
  if has_key(bindings, string(number))
    bindings[string(number)].ResumeQueuedRegistration(ticket)
  endif
enddef

export def ApplyRegistrationResult(number: number, ticket: number)
  if has_key(bindings, string(number))
    bindings[string(number)].ApplyQueuedRegistration(ticket)
  endif
enddef

def RequireCurrentBinding(): Binding
  const id = string(bufnr('%'))
  if !has_key(bindings, id)
    throw 'caskk: no current dictionary registration request'
  endif
  return bindings[id]
enddef

export def GetRegistrationRequest(): registration.Request
  const id = string(bufnr('%'))
  return has_key(bindings, id) ? bindings[id].GetRegistrationRequest() : null_object
enddef

export def CompleteRegistration(text: string, annotations: list<string> = [])
  RequireCurrentBinding().CompleteRegistration(text, annotations)
enddef

export def CancelRegistration()
  RequireCurrentBinding().CancelRegistration()
enddef

export def Enable(compiled: scheme.CompiledScheme, sticky_key: string = '', actions: dict<string> = {},
    entries: dict<dictionary.Entry> = {}, preferences: user_state.State = null_object)
  if !has_key(bindings, string(bufnr('%')))
    const current = Binding.new(compiled, sticky_key, entries, preferences, actions)
    current.Enable()
  endif
enddef

export def Disable()
  const id = string(bufnr('%'))
  if has_key(bindings, id)
    bindings[id].Disable()
  endif
enddef

export def IsEnabled(): bool
  return has_key(bindings, string(bufnr('%')))
enddef

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

# InsertCharPre is text-locked. Suppress native insertion and queue the same
# semantic input before the remaining typeahead, without editing in the event.
def BeforeCharacter(number: number)
  if !has_key(bindings, string(number)) || char2nr(v:char) < 0x80
    return
  endif
  const text = v:char
  v:char = ''
  var queued = ''
  for key in split(text, '\zs')
    queued ..= "\<Cmd>call caskk#binding#DispatchInput(" .. number .. ', ' .. string(key) .. ")\<CR>"
  endfor
  feedkeys(queued, 'in')
enddef

# Native queued commands need a fully qualified autoload entry point.
export def DispatchInput(number: number, key: string)
  Dispatch(number, key)
enddef

augroup caskk_input
augroup END
