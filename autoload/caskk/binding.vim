vim9script

import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/insert.vim' as insert
import autoload 'caskk/session.vim' as session
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/input/keycode.vim' as keycode
import autoload 'caskk/input/mapping.vim' as mapping
import autoload 'caskk/input/mapping_state.vim' as mapping_state
import autoload 'caskk/input/mode.vim' as input_mode
import autoload 'caskk/presentation/mode_popup.vim' as mode_popup
import autoload 'caskk/presentation/registration_inline.vim' as registration_inline
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/index.vim' as dict_index
import 'caskk/registration.vim' as registration
import autoload 'caskk/registration/window.vim' as registration_window
import autoload 'caskk/registration/editor.vim' as registration_editor
import autoload 'caskk/registration/text.vim' as registration_text
import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/completion.vim' as completion
import 'caskk/reconversion.vim' as reconversion

const NATIVE_KEYS = ['<Left>', '<Right>', '<Up>', '<Down>', '<Home>', '<End>', '<CR>', '<Tab>', '<BS>', '<C-H>', '<Del>', '<Nul>']
const INLINE_GUARD_KEYS = ['<C-A>', '<C-B>', '<C-D>', '<C-E>', '<C-F>', '<C-G>', '<C-H>', '<C-I>',
  '<C-J>', '<C-K>', '<C-L>', '<C-M>', '<C-N>', '<C-O>', '<C-P>', '<C-Q>', '<C-R>', '<C-S>',
  '<C-T>', '<C-U>', '<C-V>', '<C-W>', '<C-X>', '<C-Y>', '<C-Z>', '<S-Tab>', '<PageUp>',
  '<PageDown>', '<Insert>', '<F1>', '<F2>', '<F3>', '<F4>', '<F5>', '<F6>', '<F7>', '<F8>',
  '<F9>', '<F10>', '<F11>', '<F12>']

export class Binding
  const _buffer: number
  const _compiled: scheme.CompiledScheme
  const _sticky: string
  const _entries: dict<dictionary.Entry>
  const _dictionary_index: dict_index.Database
  const _preferences: user_state.State
  const _actions: dict<string>
  const _keys: dict<string>
  const _native: dict<bool>
  const _registration_auto: bool
  const _small_tsu_okuri_as_t: bool
  const _keyboard_layout: string
  const _keyboard_layout_overrides: dict<string>
  const _persist_input_mode: bool
  const _keep_preedit_on_backspace: bool
  const _register_mode_conversions: bool
  const _mode_view: mode_popup.View
  const _inline_view: registration_inline.View
  const _reconversion_history: reconversion.History
  const _mappings = mapping_state.State.new()
  const _inline_mappings = mapping_state.State.new()
  const _delete_mappings = mapping_state.State.new()
  const _reconversion_mappings = mapping_state.State.new()
  var _completion_timer: number = -1
  var _completion_select: bool = false
  var _completion_search: completion.Search = null_object
  var _completion_editor: insert.Editor = null_object
  var _editor: insert.Editor = null_object
  var _enabled: bool = false
  var _registration_reply: dictionary.Candidate = null_object
  var _registration_ticket: number = 0
  var _initial_reading: string = ''
  var _registration_window: registration_window.Window = null_object
  var _window_result: dictionary.Candidate = null_object
  var _window_closing: bool = false
  var _input_mode: string = input_mode.HIRAGANA
  var _mode_marker: string = ''
  var _inline_editor: registration_editor.Editor = null_object
  var _disabled_during_inline_registration: bool = false
  var _delete_user_entry_pending: bool = false
  var _reconversion_pending: conversion.Candidates = null_object
  var _reconversion_record: reconversion.Record = null_object
  var _reconversion_start: list<number> = []

  def new(compiled: scheme.CompiledScheme, sticky_key: string = '',
      entries: dict<dictionary.Entry> = {}, preferences: user_state.State = null_object,
      actions: dict<string> = {}, initial_reading: string = '', registration_auto: bool = false,
      small_tsu_okuri_as_t: bool = true, keyboard_layout: string = '',
      keyboard_layout_overrides: dict<string> = {}, persist_input_mode: bool = false,
      register_mode_conversions: bool = true, dictionary_index: dict_index.Database = null_object,
      reconversion_history: reconversion.History = null_object, keep_preedit_on_backspace: bool = true)
    this._buffer = bufnr('%')
    this._compiled = compiled
    this._sticky = sticky_key
    this._entries = copy(entries)
    this._dictionary_index = dictionary_index
    this._preferences = preferences is null_object ? user_state.State.new() : preferences
    this._actions = copy(actions)
    this._initial_reading = initial_reading
    this._registration_auto = registration_auto
    this._small_tsu_okuri_as_t = small_tsu_okuri_as_t
    this._keyboard_layout = keyboard_layout
    this._keyboard_layout_overrides = copy(keyboard_layout_overrides)
    this._persist_input_mode = persist_input_mode
    this._register_mode_conversions = register_mode_conversions
    this._keep_preedit_on_backspace = keep_preedit_on_backspace
    this._mode_view = mode_popup.View.new()
    this._inline_view = registration_inline.View.new()
    this._reconversion_history = reconversion_history is null_object
      ? reconversion.History.new() : reconversion_history
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
    this._mappings.Restore()
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
        if this._mappings.Owns(lhs)
          throw 'caskk: duplicate physical mapping: ' .. key
        endif
        var argument = substitute(string(key), '<', '<lt>', 'g')
        argument = substitute(argument, '\\', '<Bslash>', 'g')
        argument = substitute(argument, '|', '<Bar>', 'g')
        this._mappings.Install(lhs, '<Cmd>call caskk#binding#DispatchInput(' .. this._buffer .. ', ' .. argument .. ')<CR>')
      endfor
      bindings[id] = this
      this._enabled = true
      execute 'autocmd caskk_input InsertEnter <buffer=' .. this._buffer .. '> OnInsertEnter(' .. this._buffer .. ')'
      execute 'autocmd caskk_input InsertCharPre <buffer=' .. this._buffer .. '> BeforeCharacter(' .. this._buffer .. ')'
      execute 'autocmd caskk_input InsertLeave,BufLeave,WinLeave <buffer=' .. this._buffer .. '> Leave(' .. this._buffer .. ')'
      execute 'autocmd caskk_input BufWipeout <buffer=' .. this._buffer .. '> Forget(' .. this._buffer .. ')'
      execute 'autocmd! caskk_reconversion_history * <buffer=' .. this._buffer
        .. '>'
      execute 'autocmd caskk_reconversion_history BufWipeout <buffer=' .. this._buffer
        .. '> call caskk#binding#ForgetReconversion(' .. this._buffer .. ')'
      const owner = get(reconversion_owners, id, null_object)
      if mode(1) =~# '^i' && (owner is null_object || !owner.HasActiveReconversion())
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
    if !force && this._inline_editor isnot null_object
      this._CommitInlineComposition()
      this._enabled = false
      this._disabled_during_inline_registration = true
      this._mode_view.Close()
      return
    endif
    this._DisableCompletely()
  enddef

  def _DisableCompletely()
    if this.HasActiveReconversion()
      this._DisableForReconversion()
      return
    endif
    if this._registration_window isnot null_object
      this.SubmitRegistrationWindow(this._registration_window.buffer, true)
    endif
    try
      this.Leave(true)
    finally
      this._ClearRegistrationReply()
      execute 'autocmd! caskk_input * <buffer=' .. this._buffer .. '>'
      const id = string(this._buffer)
      if has_key(reconversion_owners, id) && reconversion_owners[id].HasActiveReconversion()
        reconversion_owners[id].PrepareForBindingDisable(this)
      endif
      this._Restore()
      remove(bindings, id)
      this._enabled = false
      this._mode_view.Close()
      this._CloseInlineInput()
    endtry
  enddef

  def _DisableForReconversion()
    execute 'autocmd! caskk_input * <buffer=' .. this._buffer .. '>'
    const id = string(this._buffer)
    this._Restore()
    remove(bindings, id)
    this._enabled = false
    this._mode_view.Close()
    this._CloseInlineInput()
    this._InstallReconversionActionMappings()
    execute 'autocmd caskk_reconversion InsertLeave,BufLeave,WinLeave <buffer='
      .. this._buffer .. '> call caskk#binding#CancelReconversion(' .. this._buffer .. ')'
    execute 'autocmd caskk_reconversion BufWipeout <buffer=' .. this._buffer
      .. '> call caskk#binding#ForgetReconversion(' .. this._buffer .. ')'
  enddef

  def _InstallReconversionActionMappings()
    for [key, action] in items(this._actions)
      if action !=# 'Convert' && action !=# 'Commit'
        continue
      endif
      const lhs = this._keys[key]
      this._reconversion_mappings.Install(lhs, '<Cmd>call caskk#binding#ReconversionInput('
        .. this._buffer .. ', ' .. string(key) .. ')<CR>')
    endfor
  enddef

  def _FinishDeferredDisable()
    if !this._disabled_during_inline_registration
      return
    endif
    this._disabled_during_inline_registration = false
    this._DisableCompletely()
  enddef

  def _Record(results: list<session.Result>)
    var requested = false
    var committed_conversion = false
    for result in results
      if !empty(result.unhandled)
        throw 'caskk: native handling of unhandled input is not connected'
      endif
      requested = requested || result.registration_requested
      if result.dictionary_loading
        echomsg 'Caskk: dictionary is still loading; press Convert again when loading finishes'
      endif
      if result.commit_preedit && this._reconversion_pending isnot null_object
        const prepared = this._reconversion_pending
        this._reconversion_history.Add(result.text, prepared.query.reading, prepared.okuri,
          prepared.query.exact_okuri)
        this._reconversion_pending = null_object
        committed_conversion = true
      endif
    endfor
    if this._editor isnot null_object && this._editor.IsInCandidate()
      this._reconversion_pending = this._editor.GetCandidates()
    elseif !committed_conversion && !empty(results)
      this._reconversion_pending = null_object
    endif
    if committed_conversion
      this._reconversion_record = null_object
      this._reconversion_start = []
    endif
    if this._registration_auto && requested && this._editor isnot null_object
        && !this._editor.IsRegistrationSuspended() && this._editor.GetRegistrationRequest() isnot null_object
      this.OpenRegistrationWindow(configuration.GetRegistrationPrefill())
    endif
    this._SyncInputMode()
  enddef

  def _SaveChangedUserState(previous_revision: number)
    if this._preferences isnot user_runtime.Get() || !configuration.GetStateAuto()
        || this._preferences.Revision() == previous_revision
      return
    endif
    const error = user_runtime.SaveAutomaticIfChanged(configuration.GetStatePath())
    if error !=# ''
      echohl ErrorMsg
      echomsg error
      echohl None
    endif
  enddef

  def _SyncInputMode()
    if this._editor is null_object
      return
    endif
    const mode = this._editor.GetInputMode()
    const snapshot = this._editor.GetSnapshot()
    const marker = this._editor.IsInCandidate() || this._editor.IsInCompletion() ? 'candidate'
      : snapshot.in_preedit || this._editor.HasPendingModifier() ? 'modified' : ''
    this._input_mode = mode
    this._mode_marker = marker
    this._mode_view.Show(mode, marker)
  enddef

  def _AbandonExternallyChangedEditor(): bool
    if this._editor is null_object || this._editor.IsBufferCurrent()
      return false
    endif
    # Keep external edits intact; the old editor's tracked range and undo tick
    # can no longer safely be applied to the changed buffer.
    if this._inline_editor isnot null_object
      this._CloseInlineInput()
    endif
    this._editor.Abandon()
    this._editor = null_object
    this._mode_marker = ''
    this._mode_view.Close()
    return true
  enddef

  def _RefreshInlinePopup(message: string = '')
    if this._inline_editor is null_object
      return
    endif
    this._inline_view.ShowEditor(this.GetRegistrationRequest(), this._inline_editor, message)
    const marker = this._inline_editor.Marker()
    const mode = this._inline_editor.input.GetInputMode()
    this._mode_view.Show(mode, marker, false, this._inline_view.ModeAnchor())
    this._input_mode = mode
    this._mode_marker = marker
  enddef

  def _AppendInlineResults(results: list<session.Result>)
    this._inline_editor.Append(results)
    this._RefreshInlinePopup()
  enddef

  def _CommitInlineComposition()
    this._inline_editor.Commit()
    this._RefreshInlinePopup()
  enddef

  def _CloseInlineInput(restore_escape: bool = true)
    this._delete_user_entry_pending = false
    this._inline_view.Close()
    this._mode_view.Close()
    this._mode_marker = ''
    this._inline_editor = null_object
    if restore_escape
      this.RestoreInlineEscape()
    endif
  enddef

  def RestoreInlineEscape()
    this._inline_mappings.RestoreKey(mapping.Lhs('<Esc>'))
    this._inline_mappings.RestoreKey(mapping.Lhs('<C-C>'))
    this._inline_mappings.Restore()
  enddef

  def _InstallInlineGuards()
    const paste_lhs = '<PasteStart>'
    this._inline_mappings.Install(paste_lhs, '<Cmd>call caskk#binding#PasteInline(' .. this._buffer .. ')<CR>')
    final seen: dict<bool> = {}
    for key in INLINE_GUARD_KEYS
      const lhs = mapping.Lhs(key)
      if has_key(seen, lhs) || index(values(this._keys), lhs) >= 0
        continue
      endif
      seen[lhs] = true
      this._inline_mappings.Install(lhs, '<Nop>')
    endfor
  enddef

  def _InstallInlineEscape()
    const lhs = mapping.Lhs('<Esc>')
    var argument = substitute(string('<Esc>'), '<', '<lt>', 'g')
    argument = substitute(argument, '\\', '<Bslash>', 'g')
    argument = substitute(argument, '|', '<Bar>', 'g')
    this._inline_mappings.Install(lhs, '<Cmd>call caskk#binding#DispatchInput('
      .. this._buffer .. ', ' .. argument .. ')<CR>')
  enddef

  def _OpenInlineRegistration(prefill: bool)
    if this._inline_editor isnot null_object
      throw 'caskk: inline registration is already open'
    endif
    this.SuspendRegistration()
    const request = this.GetRegistrationRequest()
    try
      this._mode_view.Close()
      this._inline_editor = registration_editor.Editor.new(session.Session.new(this._compiled, this._sticky, this._entries,
        this._preferences, prefill ? request.reading : '', this._small_tsu_okuri_as_t,
        this._keyboard_layout, this._keyboard_layout_overrides, this._input_mode,
        this._register_mode_conversions, this._dictionary_index, '', this._keep_preedit_on_backspace))
      this._InstallInlineEscape()
      const interrupt_lhs = mapping.Lhs('<C-C>')
      var interrupt_argument = substitute(string('<C-C>'), '<', '<lt>', 'g')
      interrupt_argument = substitute(interrupt_argument, '\\', '<Bslash>', 'g')
      interrupt_argument = substitute(interrupt_argument, '|', '<Bar>', 'g')
      this._inline_mappings.Install(interrupt_lhs, '<Cmd>call caskk#binding#DispatchInput(' .. this._buffer .. ', '
        .. interrupt_argument .. ')<CR>')
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
    if this._inline_editor.input.InCandidate() || this._inline_editor.input.GetSnapshot().in_preedit
      this._AppendInlineResults(this._inline_editor.input.Commit())
    endif
    const candidate = registration_text.Parse(this._inline_editor.GetText())
    if candidate.text ==# ''
      this._RefreshInlinePopup('登録語を入力してください')
      return
    endif
    this._CloseInlineInput()
    this._editor.ResumeRegistration()
    this._Record([this._editor.Register(candidate)])
    this._FinishDeferredDisable()
  enddef

  def PasteInline()
    this._CheckTarget()
    var text = ''
    while true
      const key = getcharstr()
      if key ==# "\<PasteEnd>"
        break
      endif
      text ..= key
    endwhile
    if text ==# '' || this._AbandonExternallyChangedEditor() || this._inline_editor is null_object
      return
    endif
    const previous_revision = this._preferences.Revision()
    try
      this._inline_editor.Paste(text)
      this._RefreshInlinePopup()
    finally
      this._SaveChangedUserState(previous_revision)
    endtry
  enddef

  def _FeedInline(key: string)
    this._AppendInlineResults(this._inline_editor.input.Feed(key ==# '<Space>' ? ' ' : key))
  enddef

  def _CanRunInlineCandidateAction(action: string): bool
    if action ==# 'DeleteUserEntry'
      return this._inline_editor.input.CanDeleteUserEntry()
    endif
    return index(['Convert', 'NextCandidate', 'PreviousCandidate', 'Commit',
      'TogglePin', 'ToggleDemote', 'AbbreviationMode'], action) >= 0
  enddef

  def _DispatchInline(key: string)
    if this._ResolveDeleteUserEntryConfirmation(key)
      return
    endif
    if key ==# '<Esc>'
      if this._inline_editor.input.InCandidate()
        this._AppendInlineResults(this._inline_editor.input.Commit())
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
    elseif (key ==# '<BS>' || key ==# '<C-H>')
        && (!this._inline_editor.input.InCandidate() || has_key(this._native, key)
          || (has_key(this._actions, key) && !this._CanRunInlineCandidateAction(this._actions[key])))
      if this._inline_editor.input.BackspacePending()
        this._RefreshInlinePopup()
      else
        const result = this._inline_editor.input.BackspacePreedit()
        if result isnot null_object
          this._RefreshInlinePopup()
        else
          this._CommitInlineComposition()
          this._inline_editor.Delete(true)
          this._RefreshInlinePopup()
        endif
      endif
      return
    elseif key ==# '<Left>' || key ==# '<Right>'
      this._inline_editor.Move(key ==# '<Left>' ? -1 : 1)
      this._RefreshInlinePopup()
      return
    elseif key ==# '<Del>'
      this._CommitInlineComposition()
      this._inline_editor.Delete(false)
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
        this._inline_editor.InsertLiteral(literal)
        this._RefreshInlinePopup()
      endif
      return
    endif

    const action = get(this._actions, key, '')
    if action !=# '' && this._inline_editor.input.IsSpecialContinuation(key)
      this._AppendInlineResults(this._inline_editor.input.Feed(key))
      return
    endif
    if action ==# 'ShowCompletion' || action ==# 'CancelCompletion'
      return
    elseif action ==# 'Convert'
      if this._inline_editor.input.InCandidate()
        this._AppendInlineResults([this._inline_editor.input.NextCandidate()])
      else
        const results = this._inline_editor.input.StartConversion(this._entries, this._preferences)
        if empty(results)
          this._FeedInline(key)
        else
          this._AppendInlineResults(results)
        endif
      endif
    elseif action ==# 'NextCandidate' && this._inline_editor.input.InCandidate()
      this._AppendInlineResults([this._inline_editor.input.NextCandidate()])
    elseif action ==# 'PreviousCandidate' && this._inline_editor.input.InCandidate()
      this._AppendInlineResults([this._inline_editor.input.PreviousCandidate()])
    elseif action ==# 'TogglePin' && this._inline_editor.input.InCandidate()
      this._inline_editor.input.TogglePin()
      this._RefreshInlinePopup()
    elseif action ==# 'ToggleDemote' && this._inline_editor.input.InCandidate()
      this._inline_editor.input.ToggleDemote()
      this._RefreshInlinePopup()
    elseif action ==# 'DeleteUserEntry' && this._inline_editor.input.CanDeleteUserEntry()
      this._RequestDeleteUserEntryConfirmation()
    elseif action ==# 'Commit'
      this._AppendInlineResults(this._inline_editor.input.Commit())
    elseif action ==# 'OpenRegistration'
      return
    elseif mapping.ModeForAction(action) ==# input_mode.ABBREVIATION
        && this._inline_editor.input.InCandidate()
      this._AppendInlineResults(this._inline_editor.input.Commit())
      this._inline_editor.input.SetInputMode(input_mode.ABBREVIATION)
      this._RefreshInlinePopup()
    elseif mapping.ModeForAction(action) !=# '' && this._inline_editor.input.CanChangeInputMode()
      this._inline_editor.input.SetInputMode(mapping.ModeForAction(action))
      this._RefreshInlinePopup()
    elseif mapping.ModeForAction(action) !=# ''
        && this._inline_editor.input.CanCommitPreeditAsMode(mapping.ModeForAction(action))
      this._AppendInlineResults(this._inline_editor.input.CommitPreeditAsMode(mapping.ModeForAction(action)))
    else
      this._FeedInline(key)
    endif
  enddef

  def _RequestDeleteUserEntryConfirmation()
    this._delete_user_entry_pending = true
    const message = 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消'
    if this._inline_editor isnot null_object
      this._RefreshInlinePopup(message)
    elseif this._editor isnot null_object
      this._InstallDeleteEscape()
      this._editor.ShowDeleteUserEntryConfirmation(message)
    endif
  enddef

  def _InstallDeleteEscape()
    if this._delete_mappings.Has(mapping.Lhs('<Esc>'))
      return
    endif
    const lhs = mapping.Lhs('<Esc>')
    var argument = substitute(string('<Esc>'), '<', '<lt>', 'g')
    argument = substitute(argument, '\\', '<Bslash>', 'g')
    argument = substitute(argument, '|', '<Bar>', 'g')
    this._delete_mappings.Install(lhs, '<Cmd>call caskk#binding#DispatchInput('
      .. this._buffer .. ', ' .. argument .. ')<CR>')
  enddef

  def _RestoreDeleteEscape()
    this._delete_mappings.Restore()
  enddef

  def _ResolveDeleteUserEntryConfirmation(key: string): bool
    if !this._delete_user_entry_pending
      return false
    endif
    this._delete_user_entry_pending = false
    this._RestoreDeleteEscape()
    if key ==# 'y' || key ==# 'Y'
      if this._inline_editor isnot null_object && this._inline_editor.input.CanDeleteUserEntry()
        this._AppendInlineResults([this._inline_editor.input.DeleteUserEntry()])
      elseif this._editor isnot null_object && this._editor.CanDeleteUserEntry()
        this._Record([this._editor.DeleteUserEntry()])
      endif
      return true
    endif
    if this._inline_editor isnot null_object
      this._RefreshInlinePopup()
    elseif this._editor isnot null_object
      this._editor.ShowDeleteUserEntryConfirmation('')
    endif
    return key ==# 'n' || key ==# 'N' || key ==# '<Esc>'
  enddef

  def _CanRunAction(action: string): bool
    if this._editor is null_object
      return false
    endif
    const snapshot = this._editor.GetSnapshot()
    const has_candidate = this._editor.IsInCandidate()
    if action ==# 'ShowCompletion'
      return this._editor.IsInCompletion() || (!has_candidate && snapshot.in_preedit)
    elseif action ==# 'CancelCompletion'
      return this._editor.IsInCompletion()
    elseif action ==# 'Convert'
      return has_candidate || snapshot.in_preedit
    elseif action ==# 'NextCandidate' || action ==# 'PreviousCandidate'
      return has_candidate || this._editor.IsInCompletion()
    elseif action ==# 'TogglePin' || action ==# 'ToggleDemote'
      return has_candidate
    elseif action ==# 'DeleteUserEntry'
      return this._editor.CanDeleteUserEntry()
    elseif action ==# 'Commit'
      return has_candidate || snapshot.in_preedit
    elseif action ==# 'OpenRegistration'
      return this.GetRegistrationRequest() isnot null_object
    elseif mapping.ModeForAction(action) != ''
      return (mapping.ModeForAction(action) ==# input_mode.ABBREVIATION && has_candidate)
        || this._editor.CanChangeInputMode()
        || this._editor.CanCommitPreeditAsMode(mapping.ModeForAction(action))
    endif
    return false
  enddef

  def _StopCompletionSearch()
    if this._completion_timer >= 0
      timer_stop(this._completion_timer)
    endif
    if this._completion_editor isnot null_object
      this._completion_editor.CancelCompletionSearch()
    endif
    this._completion_timer = -1
    this._completion_search = null_object
    this._completion_editor = null_object
  enddef

  def _StartCompletionSearch(select: bool = false)
    this._StopCompletionSearch()
    const search = this._editor.CreateCompletionSearch(configuration.GetInput().completion_min_length)
    if search is null_object
      return
    endif
    this._completion_select = select
    this._completion_search = search
    this._completion_editor = this._editor
    this._completion_timer = timer_start(1, this._AdvanceCompletion, {repeat: -1})
  enddef

  def _AdvanceCompletion(timer: number)
    if timer != this._completion_timer
      return
    endif
    if this._editor isnot this._completion_editor || !this._enabled
        || !this._editor.CanApplyCompletion() || !this._completion_search.IsCurrent()
      this._StopCompletionSearch()
      return
    endif
    try
      if this._completion_search.Step(64)
        const shown = this._editor.ApplyCompletion(this._completion_search, this._completion_select)
        this._StopCompletionSearch()
        if shown
          this._SyncInputMode()
        endif
      endif
    catch
      this._StopCompletionSearch()
      throw v:exception
    endtry
  enddef

  def _ShowAutomaticCompletion()
    if !configuration.GetCandidatePopup() || this._editor is null_object
        || this._editor.IsRegistrationSuspended() || this._editor.IsInCompletion()
      return
    endif
    this._StartCompletionSearch()
  enddef

  def _FeedEditor(key: string)
    this._Record(this._editor.Feed(key))
    this._ShowAutomaticCompletion()
  enddef

  def _FallbackActionKey(key: string)
    const literal = key ==# '<Space>' ? ' '
      : strchars(key) == 1 && char2nr(key) >= 0x20 && char2nr(key) != 0x7f ? key : ''
    if literal !=# ''
      if this._editor is null_object
        this.Enter()
      endif
      this._FeedEditor(literal)
      return
    endif
    this.Leave()
    this._mappings.Release(this._keys[key])
    feedkeys(keycode.Encode(key) .. "\<Cmd>call caskk#binding#ReinstallActionMapping("
      .. this._buffer .. ', ' .. string(key) .. ")\<CR>\<Cmd>call caskk#binding#ResumeAfterNativeInput("
      .. this._buffer .. ")\<CR>", 'im')
  enddef

  def ReinstallActionMapping(key: string)
    if !this._enabled
      return
    endif
    var argument = substitute(string(key), '<', '<lt>', 'g')
    argument = substitute(argument, '\\', '<Bslash>', 'g')
    argument = substitute(argument, '|', '<Bar>', 'g')
    this._mappings.Reinstall(this._keys[key], '<Cmd>call caskk#binding#DispatchInput(' .. this._buffer .. ', ' .. argument .. ')<CR>')
  enddef

  def Enter()
    this._CheckTarget()
    if this._editor isnot null_object && this._editor.IsRegistrationSuspended()
      throw 'caskk: input is suspended for dictionary registration'
    endif
    const reconverting = this._reconversion_record isnot null_object && !empty(this._reconversion_start)
    if reconverting
      cursor(this._reconversion_start[0], this._reconversion_start[1])
    endif
    this._editor = insert.Editor.new(this._compiled, this._sticky, this._entries, this._preferences,
      this._initial_reading, this._small_tsu_okuri_as_t, this._keyboard_layout,
      this._keyboard_layout_overrides, this._input_mode, this._register_mode_conversions,
      this._dictionary_index,
      reconverting ? this._reconversion_record.okuri : '',
      reconverting ? this._reconversion_record.text : '',
      configuration.GetUndoRevertToReading(), this._keep_preedit_on_backspace)
    this._initial_reading = ''
    this._mode_marker = ''
    this._mode_view.Show(this._input_mode, this._mode_marker)
    if reconverting
      this._reconversion_start = []
      this._reconversion_pending = this._editor.GetCandidates()
    endif
  enddef

  def EnterOnInsertEnter()
    if this._reconversion_record isnot null_object && !empty(this._reconversion_start)
        && this._editor is null_object
      this.Enter()
      return
    endif
    const id = string(this._buffer)
    if (has_key(reconversion_owners, id) && reconversion_owners[id].HasActiveReconversion())
        || this.HasActiveReconversion()
      return
    endif
    if this._enabled && this._editor is null_object && mode(1) =~# '^i'
        && bufnr('%') == this._buffer
      this.Enter()
    endif
  enddef

  def ResumeAfterNativeInput()
    if this._enabled && mode(1) =~# '^i' && bufnr('%') == this._buffer
      this.Enter()
    endif
  enddef

  def Leave(force: bool = false)
    this._StopCompletionSearch()
    const previous_revision = this._preferences.Revision()
    try
      this._LeaveInternal(force)
    finally
      this._SaveChangedUserState(previous_revision)
    endtry
  enddef

  def _LeaveInternal(force: bool)
    this._delete_user_entry_pending = false
    this._RestoreDeleteEscape()
    if this._editor is null_object
      return
    endif
    if !force && this._editor.IsRegistrationSuspended() && this._inline_editor is null_object
      return
    endif
    if this._AbandonExternallyChangedEditor()
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
      this._reconversion_record = null_object
      this._reconversion_start = []
      this._mode_view.Close()
      this._CloseInlineInput()
    endtry
  enddef

  def Dispatch(key: string)
    const cancel_pending = this._completion_search isnot null_object
      && get(this._actions, key, '') ==# 'CancelCompletion'
    this._StopCompletionSearch()
    if cancel_pending
      return
    endif
    const previous_revision = this._preferences.Revision()
    try
      this._DispatchInput(key)
    finally
      this._SaveChangedUserState(previous_revision)
    endtry
  enddef

  def _DispatchInput(key: string)
    this._CheckTarget()
    if this._reconversion_record isnot null_object && this._editor isnot null_object
        && this._editor.IsInCandidate()
      this._CloseReconversion()
    endif
    this._AbandonExternallyChangedEditor()
    if this._ResolveDeleteUserEntryConfirmation(key)
      return
    endif
    if this._inline_editor isnot null_object
      this._DispatchInline(key)
      return
    endif
    if this._editor isnot null_object && this._editor.IsRegistrationSuspended()
      throw 'caskk: input is suspended for dictionary registration'
    endif
    if key ==# '<CR>' && this._editor isnot null_object
        && this._editor.GetInputMode() ==# input_mode.ABBREVIATION
        && this._editor.GetSnapshot().in_preedit && !this._editor.IsInCandidate()
      this._editor.CancelCompletion()
      this._Record(this._editor.Commit())
      return
    endif
    if key ==# '<CR>' && this._editor isnot null_object && this._editor.IsInCompletion()
        && this._editor.GetDisplayCandidatesInfo().selected_index < 0
      this._editor.CancelCompletion()
    endif
    if this._editor isnot null_object && this._editor.IsInCompletion()
      const completion_action = get(this._actions, key, '')
      if key ==# '<CR>' || completion_action ==# 'Commit'
        this._Record(this._editor.Commit())
        return
      elseif completion_action ==# 'ShowCompletion' || completion_action ==# 'NextCandidate'
          || (completion_action == '' && key ==# '<Down>')
        this._editor.MoveCompletion(1)
        this._SyncInputMode()
        return
      elseif completion_action ==# 'PreviousCandidate'
          || (completion_action == '' && key ==# '<Up>')
        this._editor.MoveCompletion(-1)
        this._SyncInputMode()
        return
      elseif completion_action ==# 'CancelCompletion'
        this._editor.CancelCompletion()
        this._SyncInputMode()
        return
      elseif (key ==# '<BS>' || key ==# '<C-H>')
        this._editor.CancelCompletion()
        this._editor.Backspace()
        this._reconversion_pending = null_object
        this._ShowAutomaticCompletion()
        this._SyncInputMode()
        return
      elseif strchars(key) == 1 && !has_key(this._native, key)
          && (completion_action == '' || !this._CanRunAction(completion_action))
          && this._editor.GetDisplayCandidatesInfo().selected_index >= 0
        this._Record(this._editor.Commit())
      else
        this._editor.CancelCompletion()
      endif
    endif
    if this._editor isnot null_object && this._editor.MoveWithinPreedit(key)
      this._SyncInputMode()
      return
    endif
    if this._editor isnot null_object
      this._editor.RestorePreeditCursor()
    endif
    if has_key(this._native, key)
      if (key ==# '<BS>' || key ==# '<C-H>') && this._editor isnot null_object && this._editor.Backspace()
        this._reconversion_pending = null_object
        this._ShowAutomaticCompletion()
        this._SyncInputMode()
        return
      endif
      # End the IME transaction before native motion or editing. Replay ahead
      # of later input without remapping back into this binding.
      this.Leave()
      feedkeys(keycode.Encode(key) .. "\<Cmd>call caskk#binding#ResumeAfterNativeInput("
        .. this._buffer .. ")\<CR>", 'in')
      return
    endif
    if this._editor is null_object
      this.Enter()
    endif
    const action = get(this._actions, key, '')
    if action !=# '' && this._editor.IsSpecialContinuation(key)
      this._FeedEditor(key)
      return
    endif
    if (key ==# '<BS>' || key ==# '<C-H>') && action !=# '' && !this._CanRunAction(action)
      if this._editor.Backspace()
        this._reconversion_pending = null_object
        this._ShowAutomaticCompletion()
        this._SyncInputMode()
        return
      endif
    endif
    if action !=# '' && !this._CanRunAction(action)
      this._FallbackActionKey(key)
    elseif action ==# 'ShowCompletion'
      this._StartCompletionSearch(true)
      this._SyncInputMode()
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
    elseif action ==# 'DeleteUserEntry'
      this._RequestDeleteUserEntryConfirmation()
    elseif action ==# 'Commit'
      this._Record(this._editor.Commit())
    elseif action ==# 'OpenRegistration'
      this.OpenRegistrationWindow(configuration.GetRegistrationPrefill())
    elseif mapping.ModeForAction(action) ==# input_mode.ABBREVIATION && this._editor.IsInCandidate()
      this._Record(this._editor.Commit())
      this._editor.SetInputMode(input_mode.ABBREVIATION)
      this._input_mode = this._editor.GetInputMode()
      this._mode_marker = ''
      this._mode_view.Show(this._input_mode, this._mode_marker)
    elseif mapping.ModeForAction(action) != ''
      const mode = mapping.ModeForAction(action)
      if this._editor.CanCommitPreeditAsMode(mode)
        this._Record(this._editor.CommitPreeditAsMode(mode))
      else
        this._editor.SetInputMode(mode)
        this._input_mode = this._editor.GetInputMode()
        this._mode_marker = ''
        this._mode_view.Show(this._input_mode, this._mode_marker)
      endif
    else
      this._FeedEditor(key)
    endif
  enddef

  def RestoreReconversionMappings()
    this._reconversion_mappings.Restore()
  enddef

  def _CloseReconversion()
    this.RestoreReconversionMappings()
    execute 'autocmd! caskk_reconversion * <buffer=' .. this._buffer .. '>'
    this._reconversion_record = null_object
    this._reconversion_start = []
    if !this._enabled && this._editor isnot null_object
      this._editor.Abandon()
      this._editor = null_object
    endif
    const id = string(this._buffer)
    if has_key(bindings, id) && bindings[id].IsEnabled() && mode(1) =~# '^i'
      bindings[id].ResumeAfterReconversion()
    endif
  enddef

  def Reconvert(): bool
    this._CheckTarget()
    if !&l:modifiable || mode(1) !~# '^n'
        || this.HasActiveReconversion()
      return false
    endif
    const current_line = getline('.')
    const start_column = col('.')
    const record = this._reconversion_history.Find(strpart(current_line, start_column - 1))
    if record is null_object
      return false
    endif
    const prepared = conversion.Prepare(this._entries, this._preferences, record.reading, record.okuri,
      this._small_tsu_okuri_as_t, this._dictionary_index)
    if empty(prepared.candidates)
      return false
    endif
    this._reconversion_record = record
    this._reconversion_start = [line('.'), start_column]
    this._initial_reading = record.reading
    if !this._enabled
      this._InstallReconversionActionMappings()
      execute 'autocmd caskk_reconversion InsertEnter <buffer=' .. this._buffer
        .. '> call caskk#binding#EnterReconversion(' .. this._buffer .. ')'
      execute 'autocmd caskk_reconversion InsertLeave,BufLeave,WinLeave <buffer='
        .. this._buffer .. '> call caskk#binding#CancelReconversion(' .. this._buffer .. ')'
      execute 'autocmd caskk_reconversion BufWipeout <buffer=' .. this._buffer
        .. '> call caskk#binding#ForgetReconversion(' .. this._buffer .. ')'
    endif
    startinsert!
    return true
  enddef

  def ReconversionInput(key: string)
    if this._enabled
      this.Dispatch(key)
      return
    endif
    if this._editor isnot null_object && this._editor.IsInCandidate()
      const action = get(this._actions, key, '')
      if action ==# 'Convert'
        this._Record([this._editor.NextCandidate()])
      elseif action ==# 'Commit'
        this._Record(this._editor.Commit())
        this._editor.Abandon()
        this._editor = null_object
        this._CloseReconversion()
      endif
      return
    endif
    return
  enddef

  def CancelReconversion()
    if this._reconversion_record isnot null_object
      this._CloseReconversion()
    endif
  enddef

  def GetReconversionHistory(): reconversion.History
    return this._reconversion_history
  enddef

  def HasActiveReconversion(): bool
    return this._reconversion_record isnot null_object && this._editor isnot null_object
      && this._editor.IsInCandidate()
  enddef

  def PrepareForBindingDisable(active: Binding)
    if !this.HasActiveReconversion()
      return
    endif
    this._reconversion_mappings.InheritSaved(active._mappings)
  enddef

  def ResumeAfterReconversion()
    if this._enabled && this._editor is null_object && mode(1) =~# '^i'
        && bufnr('%') == this._buffer
      this.Enter()
    endif
  enddef

  def ForgetReconversion()
    this._reconversion_record = null_object
  enddef

  def Forget()
    this._StopCompletionSearch()
    this._CloseReconversion()
    const id = string(this._buffer)
    if has_key(reconversion_owners, id)
      if reconversion_owners[id] isnot this
        reconversion_owners[id].ForgetReconversion()
      endif
      remove(reconversion_owners, id)
    endif
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
    this._mappings.Forget()
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
        this._small_tsu_okuri_as_t, this._keyboard_layout, this._keyboard_layout_overrides,
        false, this._register_mode_conversions, this._dictionary_index, null_object, this._keep_preedit_on_backspace)
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
      const candidate = registration_text.Parse(text)
      if candidate.text == ''
        window.Message('登録語を入力してください  [Enter:登録 Esc:取消]')
        return
      endif
      this._window_result = candidate
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
    const previous_revision = this._preferences.Revision()
    try
      this._CompleteRegistrationInternal(text, annotations)
    finally
      this._SaveChangedUserState(previous_revision)
    endtry
  enddef

  def _CompleteRegistrationInternal(text: string, annotations: list<string>)
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
      : dictionary.Candidate.new(candidate.text, candidate.annotations, candidate.has_plain_source ? 1 : 0)
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
var reconversion_owners: dict<Binding> = {}
var next_registration_ticket: number = 0
var registration_owners: dict<Binding> = {}

export def OpenRegistration(prefill: bool = true)
  RequireCurrentBinding().OpenRegistrationWindow(prefill)
enddef

export def Reconvert(): bool
  const id = string(bufnr('%'))
  if has_key(reconversion_owners, id)
    if reconversion_owners[id].HasActiveReconversion()
      return false
    endif
    return reconversion_owners[id].Reconvert()
  endif
  return has_key(bindings, id) ? bindings[id].Reconvert() : false
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
    keyboard_layout_overrides: dict<string> = {}, persist_input_mode: bool = false,
    register_mode_conversions: bool = true, dictionary_index: dict_index.Database = null_object,
    keep_preedit_on_backspace: bool = true)
  const id = string(bufnr('%'))
  if has_key(bindings, id)
    bindings[id].Enable()
  else
    const previous_owner = get(reconversion_owners, id, null_object)
    if previous_owner isnot null_object && previous_owner.HasActiveReconversion()
      previous_owner.RestoreReconversionMappings()
      previous_owner.Enable()
      return
    endif
    const history = previous_owner is null_object ? null_object : previous_owner.GetReconversionHistory()
    const current = Binding.new(compiled, sticky_key, entries, preferences, actions, '', registration_auto,
      small_tsu_okuri_as_t, keyboard_layout, keyboard_layout_overrides, persist_input_mode,
      register_mode_conversions, dictionary_index, history, keep_preedit_on_backspace)
    current.Enable()
    reconversion_owners[id] = current
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

export def ReconversionInput(number: number, key: string)
  if has_key(reconversion_owners, string(number))
    reconversion_owners[string(number)].ReconversionInput(key)
  endif
enddef

export def CancelReconversion(number: number)
  if has_key(reconversion_owners, string(number))
    reconversion_owners[string(number)].CancelReconversion()
  endif
enddef

export def ForgetReconversion(number: number)
  const id = string(number)
  if has_key(reconversion_owners, id)
    reconversion_owners[id].ForgetReconversion()
    remove(reconversion_owners, id)
  endif
enddef

def Dispatch(number: number, key: string)
  if has_key(reconversion_owners, string(number))
      && reconversion_owners[string(number)].HasActiveReconversion()
      && has_key(bindings, string(number))
      && reconversion_owners[string(number)] isnot bindings[string(number)]
    reconversion_owners[string(number)].CancelReconversion()
  endif
  if has_key(bindings, string(number))
    bindings[string(number)].Dispatch(key)
  endif
enddef

export def PasteInline(number: number)
  if has_key(bindings, string(number))
    bindings[string(number)].PasteInline()
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

def OnInsertEnter(number: number)
  if has_key(bindings, string(number))
    feedkeys("\<Cmd>call caskk#binding#EnterAfterInsertEnter(" .. number .. ")\<CR>", 'in')
  endif
enddef

export def EnterAfterInsertEnter(number: number)
  if has_key(bindings, string(number))
    bindings[string(number)].EnterOnInsertEnter()
  endif
enddef

export def EnterReconversion(number: number)
  const id = string(number)
  if has_key(reconversion_owners, id)
    feedkeys("\<Cmd>call caskk#binding#EnterReconversionNow(" .. number .. ")\<CR>", 'in')
  endif
enddef

export def EnterReconversionNow(number: number)
  const id = string(number)
  if has_key(reconversion_owners, id)
    reconversion_owners[id].EnterOnInsertEnter()
  endif
enddef

export def ResumeAfterNativeInput(number: number)
  if has_key(bindings, string(number))
    bindings[string(number)].ResumeAfterNativeInput()
  endif
enddef

export def ReinstallActionMapping(number: number, key: string)
  if has_key(bindings, string(number))
    bindings[string(number)].ReinstallActionMapping(key)
  endif
enddef

augroup caskk_input
augroup END

augroup caskk_reconversion
augroup END

augroup caskk_reconversion_history
augroup END
