vim9script

import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/insert.vim' as insert
import autoload 'caskk/session.vim' as session
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/input/keycode.vim' as keycode
import autoload 'caskk/input/mapping.vim' as mapping
import autoload 'caskk/input/mode.vim' as input_mode
import autoload 'caskk/presentation/mode_popup.vim' as mode_popup
import autoload 'caskk/presentation/candidate.vim' as candidate_view
import autoload 'caskk/presentation/registration_inline.vim' as registration_inline
import 'caskk/dictionary.vim' as dictionary
import 'caskk/registration.vim' as registration
import autoload 'caskk/registration/window.vim' as registration_window
import autoload 'caskk/config.vim' as configuration

const NATIVE_KEYS = ['<Left>', '<Right>', '<Up>', '<Down>', '<Home>', '<End>', '<CR>', '<Tab>', '<BS>', '<Del>']
const INLINE_GUARD_KEYS = ['<C-A>', '<C-B>', '<C-D>', '<C-E>', '<C-F>', '<C-G>', '<C-H>', '<C-I>',
  '<C-J>', '<C-K>', '<C-L>', '<C-M>', '<C-N>', '<C-O>', '<C-P>', '<C-Q>', '<C-R>', '<C-S>',
  '<C-T>', '<C-U>', '<C-V>', '<C-W>', '<C-X>', '<C-Y>', '<C-Z>', '<S-Tab>', '<PageUp>',
  '<PageDown>', '<Insert>', '<F1>', '<F2>', '<F3>', '<F4>', '<F5>', '<F6>', '<F7>', '<F8>',
  '<F9>', '<F10>', '<F11>', '<F12>']

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
  const _registration_auto: bool
  const _small_tsu_okuri_as_t: bool
  const _keyboard_layout: string
  const _keyboard_layout_overrides: dict<string>
  const _persist_input_mode: bool
  const _mode_view: mode_popup.View
  const _inline_view: registration_inline.View
  var _saved: dict<Mapping> = {}
  var _installed: dict<Mapping> = {}
  var _editor: insert.Editor = null_object
  var _last: list<session.Result> = []
  var _enabled: bool = false
  var _registration_reply: dictionary.Candidate = null_object
  var _registration_ticket: number = 0
  var _initial_reading: string = ''
  var _registration_window: registration_window.Window = null_object
  var _window_result: dictionary.Candidate = null_object
  var _window_closing: bool = false
  var _input_mode: string = input_mode.HIRAGANA
  var _mode_marker: string = ''
  var _inline_mode_view_active: bool = false
  var _inline_input: session.Session = null_object
  var _inline_text: string = ''
  var _inline_cursor: number = 0
  var _disabled_during_inline_registration: bool = false
  var _inline_escape_saved: Mapping = null_object
  var _inline_escape_installed: Mapping = null_object
  var _inline_interrupt_saved: Mapping = null_object
  var _inline_interrupt_installed: Mapping = null_object
  var _inline_guard_saved: dict<Mapping> = {}
  var _inline_guard_installed: dict<Mapping> = {}

  def new(compiled: scheme.CompiledScheme, sticky_key: string = '',
      entries: dict<dictionary.Entry> = {}, preferences: user_state.State = null_object,
      actions: dict<string> = {}, initial_reading: string = '', registration_auto: bool = false,
      small_tsu_okuri_as_t: bool = true, keyboard_layout: string = '',
      keyboard_layout_overrides: dict<string> = {}, persist_input_mode: bool = false)
    this._buffer = bufnr('%')
    this._compiled = compiled
    this._sticky = sticky_key
    this._entries = copy(entries)
    this._preferences = preferences is null_object ? user_state.State.new() : preferences
    this._actions = copy(actions)
    this._initial_reading = initial_reading
    this._registration_auto = registration_auto
    this._small_tsu_okuri_as_t = small_tsu_okuri_as_t
    this._keyboard_layout = keyboard_layout
    this._keyboard_layout_overrides = copy(keyboard_layout_overrides)
    this._persist_input_mode = persist_input_mode
    this._mode_view = mode_popup.View.new()
    this._inline_view = registration_inline.View.new()
    final tokens: dict<bool> = {}
    for key in keys(compiled.table.combinations)
      tokens[key] = true
    endfor
    for key in keys(compiled.table.consonants)
      for token in scheme.ConsonantKeys(key)
        tokens[token] = true
      endfor
    endfor
    for key in keys(compiled.table.symbols)
      for token in scheme.ConsonantKeys(key)
        tokens[token] = true
      endfor
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
    if this._disabled_during_inline_registration
      this._enabled = true
      this._disabled_during_inline_registration = false
      this._RefreshInlinePopup()
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
      this._mode_view.Close()
      this._CloseInlineInput()
      throw reason
    endtry
  enddef

  def Disable(force: bool = false)
    if !this._enabled
      return
    endif
    this._CheckTarget()
    if !force && this._inline_input isnot null_object
      this._CommitInlineComposition()
      this._enabled = false
      this._disabled_during_inline_registration = true
      this._mode_view.Close()
      this._inline_mode_view_active = false
      return
    endif
    this._DisableCompletely()
  enddef

  def _DisableCompletely()
    if this._registration_window isnot null_object
      this.SubmitRegistrationWindow(this._registration_window.buffer, true)
    endif
    try
      this.Leave(true)
    finally
      this._ClearRegistrationReply()
      execute 'autocmd! caskk_input * <buffer=' .. this._buffer .. '>'
      this._Restore()
      remove(bindings, string(this._buffer))
      this._enabled = false
      this._mode_view.Close()
      this._CloseInlineInput()
    endtry
  enddef

  def _FinishDeferredDisable()
    if !this._disabled_during_inline_registration
      return
    endif
    this._disabled_during_inline_registration = false
    this._DisableCompletely()
  enddef

  def _Record(results: list<session.Result>)
    this._last = copy(results)
    var requested = false
    for result in results
      if !empty(result.unhandled)
        throw 'caskk: native handling of unhandled input is not connected'
      endif
      requested = requested || result.registration_requested
    endfor
    if this._registration_auto && requested && this._editor isnot null_object
        && !this._editor.IsRegistrationSuspended() && this._editor.GetRegistrationRequest() isnot null_object
      this.OpenRegistrationWindow(configuration.GetRegistrationPrefill())
    endif
    this._SyncInputMode()
  enddef

  def _SyncInputMode()
    if this._editor is null_object
      return
    endif
    const mode = this._editor.GetInputMode()
    const snapshot = this._editor.GetSnapshot()
    const marker = this._editor.IsInCandidate() ? 'candidate' : snapshot.in_preedit ? 'modified' : ''
    if configuration.GetModePopupTime() == 0
        || mode !=# this._input_mode || marker !=# this._mode_marker
      this._input_mode = mode
      this._mode_marker = marker
      this._mode_view.Show(mode, marker)
    endif
  enddef

  def _InlineHeader(): string
    const request = this.GetRegistrationRequest()
    if request is null_object
      return '辞書登録'
    endif
    return '辞書登録: ' .. request.reading .. (request.okuri == '' ? '' : '*' .. request.okuri)
  enddef

  def _RefreshInlinePopup(message: string = '')
    if this._inline_input is null_object
      return
    endif
    final lines = [this._InlineHeader() .. '  [Enter:登録 Esc:取消]']
    var prefix = strcharpart(this._inline_text, 0, this._inline_cursor)
    var suffix = strcharpart(this._inline_text, this._inline_cursor)
    var insertion = ''
    var highlighted = false
    if this._inline_input.InCandidate()
      const info = this._inline_input.GetCandidatesInfo()
      if !empty(info.candidates)
        insertion = info.candidates[info.selected_index].text
        highlighted = true
      endif
    else
      const snapshot = this._inline_input.GetSnapshot()
      if snapshot.in_preedit
        insertion = input_mode.Render(snapshot.reading .. snapshot.okuri,
          this._inline_input.GetInputMode())
        highlighted = true
      endif
      for event in this._inline_input.Pending()
        insertion ..= event.key
      endfor
    endif
    lines->add('登録語: ' .. prefix .. insertion .. '│' .. suffix)
    if message !=# ''
      lines->add(message)
    elseif this._inline_input.InCandidate()
      const info = this._inline_input.GetCandidatesInfo()
      const candidates = candidate_view.Format(info)
      const visible = 6
      if len(candidates) <= visible
        lines->extend(candidates)
      else
        const start = max([0, min([info.selected_index - 2, len(candidates) - visible])])
        if start > 0
          lines->add('…')
        endif
        lines->extend(candidates[start : start + visible - 1])
        if start + visible < len(candidates)
          lines->add('…')
        endif
      endif
    endif
    const highlight_start = highlighted && insertion !=# ''
      ? strlen('登録語: ' .. prefix) + 1 : 0
    this._inline_view.Show(lines, highlight_start, strlen(insertion))
    const snapshot = this._inline_input.GetSnapshot()
    const marker = this._inline_input.InCandidate() ? 'candidate' : snapshot.in_preedit ? 'modified' : ''
    const mode = this._inline_input.GetInputMode()
    if !this._inline_mode_view_active || configuration.GetModePopupTime() == 0
        || mode !=# this._input_mode || marker !=# this._mode_marker
      this._mode_view.Show(mode, marker)
      this._inline_mode_view_active = true
      this._input_mode = mode
      this._mode_marker = marker
    endif
  enddef

  def _AppendInlineResults(results: list<session.Result>)
    for result in results
      if result.commit_preedit || (!result.in_candidate && !result.state.in_preedit && result.text !=# '')
        const prefix = strcharpart(this._inline_text, 0, this._inline_cursor)
        const suffix = strcharpart(this._inline_text, this._inline_cursor)
        this._inline_text = prefix .. result.text .. suffix
        this._inline_cursor += strchars(result.text)
      endif
    endfor
    this._RefreshInlinePopup()
  enddef

  def _CommitInlineComposition()
    if this._inline_input.InCandidate() || this._inline_input.GetSnapshot().in_preedit
        || !empty(this._inline_input.Pending())
      this._AppendInlineResults(this._inline_input.Commit())
    endif
  enddef

  def _DeleteInlineCharacter(before: bool)
    const count = strchars(this._inline_text)
    const index = before ? this._inline_cursor - 1 : this._inline_cursor
    if index < 0 || index >= count
      return
    endif
    this._inline_text = strcharpart(this._inline_text, 0, index)
      .. strcharpart(this._inline_text, index + 1)
    if before
      this._inline_cursor -= 1
    endif
  enddef

  def _CloseInlineInput(restore_escape: bool = true)
    this._inline_view.Close()
    this._mode_view.Close()
    this._inline_mode_view_active = false
    this._mode_marker = ''
    this._inline_input = null_object
    this._inline_text = ''
    this._inline_cursor = 0
    if restore_escape
      this.RestoreInlineEscape()
    endif
  enddef

  def RestoreInlineEscape()
    if this._inline_escape_installed isnot null_object
      const lhs = mapping.Lhs('<Esc>')
      if this._inline_escape_installed.MatchesCurrent(lhs)
        execute 'silent! iunmap <buffer> ' .. lhs
        this._inline_escape_saved.Restore()
      endif
      this._inline_escape_saved = null_object
      this._inline_escape_installed = null_object
    endif
    if this._inline_interrupt_installed isnot null_object
      const lhs = mapping.Lhs('<C-C>')
      if this._inline_interrupt_installed.MatchesCurrent(lhs)
        execute 'silent! iunmap <buffer> ' .. lhs
        this._inline_interrupt_saved.Restore()
      endif
      this._inline_interrupt_saved = null_object
      this._inline_interrupt_installed = null_object
    endif
    for [key, installed] in items(this._inline_guard_installed)
      const lhs = mapping.Lhs(key)
      if installed.MatchesCurrent(lhs)
        execute 'silent! iunmap <buffer> ' .. lhs
        this._inline_guard_saved[key].Restore()
      endif
    endfor
    this._inline_guard_saved = {}
    this._inline_guard_installed = {}
  enddef

  def _InstallInlineGuards()
    final seen: dict<bool> = {}
    for key in INLINE_GUARD_KEYS
      const lhs = mapping.Lhs(key)
      if has_key(seen, lhs) || index(values(this._keys), lhs) >= 0
        continue
      endif
      seen[lhs] = true
      this._inline_guard_saved[key] = Mapping.new(lhs)
      execute 'inoremap <buffer> <silent> ' .. lhs .. ' <Nop>'
      this._inline_guard_installed[key] = Mapping.new(lhs)
    endfor
  enddef

  def _InstallInlineEscape()
    const lhs = mapping.Lhs('<Esc>')
    this._inline_escape_saved = Mapping.new(lhs)
    var argument = substitute(string('<Esc>'), '<', '<lt>', 'g')
    argument = substitute(argument, '\\', '<Bslash>', 'g')
    argument = substitute(argument, '|', '<Bar>', 'g')
    execute 'inoremap <buffer> <silent> ' .. lhs .. ' <Cmd>call caskk#binding#DispatchInput('
      .. this._buffer .. ', ' .. argument .. ')<CR>'
    this._inline_escape_installed = Mapping.new(lhs)
  enddef

  def _OpenInlineRegistration(prefill: bool)
    if this._inline_input isnot null_object
      throw 'caskk: inline registration is already open'
    endif
    this.SuspendRegistration()
    const request = this.GetRegistrationRequest()
    try
      this._mode_view.Close()
      this._inline_text = ''
      this._inline_cursor = 0
      this._inline_input = session.Session.new(this._compiled, this._sticky, this._entries,
        this._preferences, prefill ? request.reading : '', this._small_tsu_okuri_as_t,
        this._keyboard_layout, this._keyboard_layout_overrides, this._input_mode)
      this._InstallInlineEscape()
      const interrupt_lhs = mapping.Lhs('<C-C>')
      this._inline_interrupt_saved = Mapping.new(interrupt_lhs)
      var interrupt_argument = substitute(string('<C-C>'), '<', '<lt>', 'g')
      interrupt_argument = substitute(interrupt_argument, '\\', '<Bslash>', 'g')
      interrupt_argument = substitute(interrupt_argument, '|', '<Bar>', 'g')
      execute 'inoremap <buffer> <silent> ' .. interrupt_lhs
        .. ' <Cmd>call caskk#binding#DispatchInput(' .. this._buffer .. ', '
        .. interrupt_argument .. ')<CR>'
      this._inline_interrupt_installed = Mapping.new(interrupt_lhs)
      this._InstallInlineGuards()
      this._RefreshInlinePopup()
    catch
      const reason = v:exception
      this._CloseInlineInput()
      this._editor.ResumeRegistration()
      throw 'caskk: cannot open inline registration: ' .. reason
    endtry
  enddef

  def _CancelInlineRegistration()
    this._CloseInlineInput(false)
    this._editor.ResumeRegistration()
    this._Record([this._editor.CancelRegistration()])
    this._FinishDeferredDisable()
    feedkeys("\<Cmd>call caskk#binding#RestoreInlineEscape(" .. this._buffer .. ")\<CR>", 'in')
  enddef

  def _AcceptInlineRegistration()
    if this._inline_input.InCandidate() || this._inline_input.GetSnapshot().in_preedit
      this._AppendInlineResults(this._inline_input.Commit())
    endif
    if this._inline_text ==# ''
      this._RefreshInlinePopup('登録語を入力してください')
      return
    endif
    const candidate = dictionary.Candidate.new(this._inline_text, [])
    this._CloseInlineInput()
    this._editor.ResumeRegistration()
    this._Record([this._editor.Register(candidate)])
    this._FinishDeferredDisable()
  enddef

  def _FeedInline(key: string)
    this._AppendInlineResults(this._inline_input.Feed(key ==# '<Space>' ? ' ' : key))
  enddef

  def _DispatchInline(key: string)
    if key ==# '<Esc>'
      if this._inline_input.InCandidate()
        this._AppendInlineResults(this._inline_input.Commit())
      else
        this._CancelInlineRegistration()
      endif
      return
    elseif key ==# '<CR>'
      this._AcceptInlineRegistration()
      return
    elseif key ==# '<C-C>'
      this._CloseInlineInput()
      this.Leave(true)
      this._FinishDeferredDisable()
      if !this._persist_input_mode
        this._input_mode = input_mode.HIRAGANA
      endif
      feedkeys(keycode.Encode(key), 'in')
      return
    elseif key ==# '<BS>'
      if this._inline_input.BackspacePending()
        this._RefreshInlinePopup()
      else
        const result = this._inline_input.BackspacePreedit()
        if result isnot null_object
          this._RefreshInlinePopup()
        else
          this._CommitInlineComposition()
          this._DeleteInlineCharacter(true)
          this._RefreshInlinePopup()
        endif
      endif
      return
    elseif key ==# '<Left>' || key ==# '<Right>'
      this._CommitInlineComposition()
      this._inline_cursor = max([0, min([strchars(this._inline_text),
        this._inline_cursor + (key ==# '<Left>' ? -1 : 1)])])
      this._RefreshInlinePopup()
      return
    elseif key ==# '<Del>'
      this._CommitInlineComposition()
      this._DeleteInlineCharacter(false)
      this._RefreshInlinePopup()
      return
    elseif has_key(this._native, key)
      # Native editing and motion outside the supported registration editor
      # are consumed so they cannot alter the suspended source buffer.
      return
    endif

    if this._disabled_during_inline_registration
      const literal = key ==# '<Space>' ? ' '
        : strchars(key) == 1 && char2nr(key) >= 0x20 && char2nr(key) != 0x7f ? key : ''
      if literal !=# ''
        const prefix = strcharpart(this._inline_text, 0, this._inline_cursor)
        const suffix = strcharpart(this._inline_text, this._inline_cursor)
        this._inline_text = prefix .. literal .. suffix
        this._inline_cursor += strchars(literal)
        this._RefreshInlinePopup()
      endif
      return
    endif

    const action = get(this._actions, key, '')
    if action ==# 'Convert'
      if this._inline_input.InCandidate()
        this._AppendInlineResults([this._inline_input.NextCandidate()])
      else
        const results = this._inline_input.StartConversion(this._entries, this._preferences)
        if empty(results)
          this._FeedInline(key)
        else
          this._AppendInlineResults(results)
        endif
      endif
    elseif action ==# 'NextCandidate' && this._inline_input.InCandidate()
      this._AppendInlineResults([this._inline_input.NextCandidate()])
    elseif action ==# 'PreviousCandidate' && this._inline_input.InCandidate()
      this._AppendInlineResults([this._inline_input.PreviousCandidate()])
    elseif action ==# 'TogglePin' && this._inline_input.InCandidate()
      this._inline_input.TogglePin()
      this._RefreshInlinePopup()
    elseif action ==# 'ToggleDemote' && this._inline_input.InCandidate()
      this._inline_input.ToggleDemote()
      this._RefreshInlinePopup()
    elseif action ==# 'Commit'
      this._AppendInlineResults(this._inline_input.Commit())
    elseif action ==# 'OpenRegistration'
      return
    elseif this._ModeForAction(action) !=# '' && this._inline_input.CanChangeInputMode()
      this._inline_input.SetInputMode(this._ModeForAction(action))
      this._RefreshInlinePopup()
    elseif this._ModeForAction(action) !=# ''
        && this._inline_input.CanCommitPreeditAsMode(this._ModeForAction(action))
      this._AppendInlineResults(this._inline_input.CommitPreeditAsMode(this._ModeForAction(action)))
    else
      this._FeedInline(key)
    endif
  enddef

  def _CanRunAction(action: string): bool
    if this._editor is null_object
      return false
    endif
    const snapshot = this._editor.GetSnapshot()
    const has_candidate = this._editor.IsInCandidate()
    if action ==# 'Convert'
      return has_candidate || snapshot.in_preedit
    elseif action ==# 'NextCandidate' || action ==# 'PreviousCandidate'
      return has_candidate
    elseif action ==# 'TogglePin' || action ==# 'ToggleDemote'
      return has_candidate
    elseif action ==# 'Commit'
      return has_candidate || snapshot.in_preedit
    elseif action ==# 'OpenRegistration'
      return this.GetRegistrationRequest() isnot null_object
    elseif this._ModeForAction(action) != ''
      return this._editor.CanChangeInputMode()
        || this._editor.CanCommitPreeditAsMode(this._ModeForAction(action))
    endif
    return false
  enddef

  def _ModeForAction(action: string): string
    if action ==# 'AbbreviationMode'
      return input_mode.ABBREVIATION
    elseif action ==# 'KatakanaMode'
      return input_mode.KATAKANA
    elseif action ==# 'HalfwidthKatakanaMode'
      return input_mode.HALFWIDTH_KATAKANA
    elseif action ==# 'FullwidthAlphanumericMode'
      return input_mode.FULLWIDTH_ALPHANUMERIC
    endif
    return ''
  enddef

  def _FallbackActionKey(key: string)
    const literal = key ==# '<Space>' ? ' '
      : strchars(key) == 1 && char2nr(key) >= 0x20 && char2nr(key) != 0x7f ? key : ''
    if literal !=# ''
      if this._editor is null_object
        this.Enter()
      endif
      this._Record(this._editor.Feed(literal))
      return
    endif
    this.Leave()
    execute 'silent! iunmap <buffer> ' .. this._keys[key]
    this._saved[key].Restore()
    feedkeys(keycode.Encode(key) .. "\<Cmd>call caskk#binding#ReinstallActionMapping("
      .. this._buffer .. ', ' .. string(key) .. ")\<CR>", 'im')
  enddef

  def ReinstallActionMapping(key: string)
    if !this._enabled
      return
    endif
    var argument = substitute(string(key), '<', '<lt>', 'g')
    argument = substitute(argument, '\\', '<Bslash>', 'g')
    argument = substitute(argument, '|', '<Bar>', 'g')
    execute 'inoremap <buffer> <silent> ' .. this._keys[key]
      .. ' <ScriptCmd>Dispatch(' .. this._buffer .. ', ' .. argument .. ')<CR>'
    this._installed[key] = Mapping.new(this._keys[key])
  enddef

  def Enter()
    this._CheckTarget()
    if this._editor isnot null_object && this._editor.IsRegistrationSuspended()
      throw 'caskk: input is suspended for dictionary registration'
    endif
    this._editor = insert.Editor.new(this._compiled, this._sticky, this._entries, this._preferences,
      this._initial_reading, this._small_tsu_okuri_as_t, this._keyboard_layout,
      this._keyboard_layout_overrides, this._input_mode)
    this._initial_reading = ''
    this._mode_marker = ''
    this._mode_view.Show(this._input_mode, this._mode_marker)
  enddef

  def Leave(force: bool = false)
    if this._editor is null_object
      return
    endif
    if !force && this._editor.IsRegistrationSuspended() && this._inline_input is null_object
      return
    endif
    try
      const active_mode = this._editor.GetInputMode()
      this._Record(this._editor.Close())
      this._input_mode = !this._persist_input_mode && mode(1) !~# '^i'
        ? input_mode.HIRAGANA : active_mode
    finally
      this._editor.Abandon()
      this._editor = null_object
      this._mode_view.Close()
      this._CloseInlineInput()
    endtry
  enddef

  def Dispatch(key: string)
    this._CheckTarget()
    if this._inline_input isnot null_object
      this._DispatchInline(key)
      return
    endif
    if this._editor isnot null_object && this._editor.IsRegistrationSuspended()
      throw 'caskk: input is suspended for dictionary registration'
    endif
    if this._editor isnot null_object && this._editor.MoveWithinPreedit(key)
      return
    endif
    if this._editor isnot null_object
      this._editor.RestorePreeditCursor()
    endif
    if has_key(this._native, key)
      if key ==# '<BS>' && this._editor isnot null_object && this._editor.Backspace()
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
    if action !=# '' && !this._CanRunAction(action)
      this._FallbackActionKey(key)
    elseif action ==# 'Convert'
      if this._editor.IsInCandidate()
        this._Record([this._editor.NextCandidate()])
      else
        this._Record(this._editor.StartConversion())
      endif
    elseif action ==# 'NextCandidate'
      this._Record([this._editor.NextCandidate()])
    elseif action ==# 'PreviousCandidate'
      this._Record([this._editor.PreviousCandidate()])
    elseif action ==# 'TogglePin'
      this._editor.TogglePin()
    elseif action ==# 'ToggleDemote'
      this._editor.ToggleDemote()
    elseif action ==# 'Commit'
      this._Record(this._editor.Commit())
    elseif action ==# 'OpenRegistration'
      this.OpenRegistrationWindow(configuration.GetRegistrationPrefill())
    elseif this._ModeForAction(action) != ''
      const mode = this._ModeForAction(action)
      if this._editor.CanCommitPreeditAsMode(mode)
        this._Record(this._editor.CommitPreeditAsMode(mode))
      else
        this._editor.SetInputMode(mode)
        this._input_mode = this._editor.GetInputMode()
        this._mode_marker = ''
        this._mode_view.Show(this._input_mode, this._mode_marker)
      endif
    else
      this._Record(this._editor.Feed(key))
    endif
  enddef

  def Forget()
    if this._registration_window isnot null_object
      this.SubmitRegistrationWindow(this._registration_window.buffer, true)
    endif
    if this._enabled
      remove(bindings, string(this._buffer))
    endif
    if this._editor isnot null_object
      this._editor.Abandon()
    endif
    this._editor = null_object
    this._ClearRegistrationReply()
    this._installed = {}
    this._saved = {}
    this._enabled = false
    this._mode_view.Close()
    this._CloseInlineInput()
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

  def OpenRegistrationWindow(prefill: bool = true)
    this._CheckTarget()
    if configuration.GetRegistrationInline()
      this._OpenInlineRegistration(prefill)
      return
    endif
    if this._registration_window isnot null_object
      throw 'caskk: dictionary registration window is already open'
    endif
    this.SuspendRegistration()
    const request = this.GetRegistrationRequest()
    try
      const window = registration_window.Open(request)
      this._registration_window = window
      registration_owners[string(this._buffer)] = this
      const child = Binding.new(this._compiled, this._sticky, this._entries,
        this._preferences, this._actions, prefill ? request.reading : '', this._registration_auto,
        this._small_tsu_okuri_as_t, this._keyboard_layout, this._keyboard_layout_overrides)
      child.Enable()
      const arguments = this._buffer .. ', ' .. window.buffer
      for command in ['inoremap', 'nnoremap']
        execute command .. ' <buffer> <silent> <CR> <Cmd>call caskk#binding#SubmitRegistrationWindow(' .. arguments .. ', v:false)<CR>'
        execute command .. ' <buffer> <silent> <Esc> <Cmd>call caskk#binding#SubmitRegistrationWindow(' .. arguments .. ', v:true)<CR>'
      endfor
      execute 'augroup ' .. window.event_group
      autocmd!
      augroup END
      execute 'autocmd ' .. window.event_group .. ' BufWipeout <buffer=' .. window.buffer .. '> call caskk#binding#SubmitRegistrationWindow(' .. arguments .. ', v:true)'
      for number in [window.window, window.origin_window]
        execute 'autocmd ' .. window.event_group .. ' WinClosed ' .. number .. ' call caskk#binding#SubmitRegistrationWindow(' .. arguments .. ', v:true)'
      endfor
    catch
      const reason = v:exception
      if this._registration_window isnot null_object
        this.SubmitRegistrationWindow(this._registration_window.buffer, true)
      elseif this._editor isnot null_object
        this._editor.PrepareRegistrationResume()
        if mode(1) =~# '^i'
          this._editor.ResumeRegistration()
        else
          this.QueueRegistrationResult()
        endif
      endif
      throw 'caskk: cannot open registration window: ' .. reason
    endtry
  enddef

  def SubmitRegistrationWindow(child: number, cancel: bool)
    const window = this._registration_window
    if window is null_object || window.buffer != child || this._window_closing
      return
    endif
    if cancel
      this._window_result = null_object
    else
      if bufnr('%') != child
        throw 'caskk: registration input buffer is not current'
      endif
      if has_key(bindings, string(child))
        bindings[string(child)].Leave()
      endif
      const text = join(getbufline(child, 1, '$'), "\n")
      if text == ''
        window.Message('登録語を入力してください  [Enter:登録 Esc:取消]')
        return
      endif
      this._window_result = dictionary.Candidate.new(text, [])
    endif
    this._window_closing = true
    feedkeys("\<Cmd>call caskk#binding#ReturnRegistrationWindow(" .. this._buffer
      .. ', ' .. child .. ")\<CR>", 'in')
  enddef

  def ReturnRegistrationWindow(child: number)
    const window = this._registration_window
    if window is null_object || window.buffer != child || !this._window_closing
      return
    endif
    const candidate = this._window_result
    var returned = false
    try
      if exists('#' .. window.event_group)
        execute 'autocmd! ' .. window.event_group
        execute 'augroup! ' .. window.event_group
      endif
      if has_key(bindings, string(child))
        # Cancellation must not implicitly commit the child's current candidate.
        bindings[string(child)].Forget()
      endif
      returned = window.Close()
    finally
      this._registration_window = null_object
      this._window_result = null_object
      this._window_closing = false
      remove(registration_owners, string(this._buffer))
    endtry
    if this._editor is null_object
      return
    endif
    if !returned || !this._enabled
      this._editor.Abandon()
      this._editor = null_object
      return
    endif
    try
      this.QueueRegistrationResult(candidate)
    catch
      const reason = v:exception
      this._editor.Abandon()
      this._editor = null_object
      throw reason
    endtry
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
var registration_owners: dict<Binding> = {}

export def OpenRegistration(prefill: bool = true)
  RequireCurrentBinding().OpenRegistrationWindow(prefill)
enddef

export def SubmitRegistrationWindow(parent: number, child: number, cancel: bool)
  if has_key(registration_owners, string(parent))
    registration_owners[string(parent)].SubmitRegistrationWindow(child, cancel)
  endif
enddef

export def ReturnRegistrationWindow(parent: number, child: number)
  if has_key(registration_owners, string(parent))
    registration_owners[string(parent)].ReturnRegistrationWindow(child)
  endif
enddef

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
    entries: dict<dictionary.Entry> = {}, preferences: user_state.State = null_object,
    registration_auto: bool = false, small_tsu_okuri_as_t: bool = true, keyboard_layout: string = '',
    keyboard_layout_overrides: dict<string> = {}, persist_input_mode: bool = false)
  if has_key(bindings, string(bufnr('%')))
    bindings[string(bufnr('%'))].Enable()
  else
    const current = Binding.new(compiled, sticky_key, entries, preferences, actions, '', registration_auto,
      small_tsu_okuri_as_t, keyboard_layout, keyboard_layout_overrides, persist_input_mode)
    current.Enable()
  endif
enddef

export def Disable()
  const id = string(bufnr('%'))
  if has_key(bindings, id)
    bindings[id].Disable()
  endif
enddef

# Configuration changes invalidate every buffer-local binding. Visit each
# target buffer so Disable() can close its editor and restore its mappings.
export def DisableAll()
  const original_window = win_getid()
  const original_buffer = bufnr('%')
  var numbers = mapnew(keys(bindings), (_, id) => str2nr(id))
  sort(numbers, 'n')
  try
    for number in numbers
      const id = string(number)
      if !has_key(bindings, id)
        continue
      endif
      if bufnr('%') != number
        const windows = win_findbuf(number)
        if !empty(windows)
          if !win_gotoid(windows[0])
            throw 'caskk: cannot visit an enabled buffer'
          endif
        else
          execute 'noautocmd keepalt hide buffer ' .. number
        endif
      endif
      if has_key(bindings, id)
        bindings[id].Disable(true)
      endif
    endfor
  finally
    if win_gotoid(original_window)
      if bufnr('%') != original_buffer && bufexists(original_buffer)
        execute 'noautocmd keepalt hide buffer ' .. original_buffer
      endif
    elseif bufexists(original_buffer)
      execute 'noautocmd keepalt hide buffer ' .. original_buffer
    endif
  endtry
enddef

export def IsEnabled(): bool
  return has_key(bindings, string(bufnr('%'))) && bindings[string(bufnr('%'))].IsEnabled()
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

export def RestoreInlineEscape(number: number)
  if has_key(bindings, string(number))
    bindings[string(number)].RestoreInlineEscape()
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

export def ReinstallActionMapping(number: number, key: string)
  if has_key(bindings, string(number))
    bindings[string(number)].ReinstallActionMapping(key)
  endif
enddef

augroup caskk_input
augroup END
