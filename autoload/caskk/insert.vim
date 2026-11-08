vim9script

import 'caskk/input.vim' as input
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/session.vim' as session
import autoload 'caskk/state.vim' as state_types
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/buffer.vim' as buffer
import autoload 'caskk/undo.vim' as undo
import autoload 'caskk/presentation.vim' as presentation
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/completion.vim' as completion
import autoload 'caskk/presentation/candidate.vim' as candidate_view
import autoload 'caskk/input/mode.vim' as input_mode

# One Insert-mode attachment. Mappings and native handling of unhandled events
# belong to a later dispatch layer; original ordered results are returned here.
export class Editor
  const _buffer: number
  const _window: number
  const _session: session.Session
  const _entries: dict<dictionary.Entry>
  const _dictionary_index: dict_index.Database
  const _preferences: user_state.State
  const _writer: buffer.Writer
  const _undo: undo.Manager
  const _view: presentation.Highlighter
  const _candidate_view: candidate_view.View
  var _closed: bool = false
  var _registration_suspended: bool = false
  var _pending_visible: bool = false

  def new(compiled: scheme.CompiledScheme, sticky_key: string = '',
      entries: dict<dictionary.Entry> = {}, preferences: user_state.State = null_object,
      initial_reading: string = '', small_tsu_okuri_as_t: bool = true, keyboard_layout: string = '',
      keyboard_layout_overrides: dict<string> = {}, input_mode_name: string = input_mode.HIRAGANA,
      register_mode_conversions: bool = true, dictionary_index: dict_index.Database = null_object,
      initial_okuri: string = '', initial_text: string = '', revert_to_reading: bool = true,
      keep_preedit_on_backspace: bool = true)
    if mode(1) !~# '^i'
      throw 'caskk: editor must be started in Insert mode'
    endif
    this._buffer = bufnr('%')
    this._window = win_getid()
    this._entries = copy(entries)
    this._dictionary_index = dictionary_index
    this._preferences = preferences is null_object ? user_state.State.new() : preferences
    this._session = session.Session.new(compiled, sticky_key, this._entries, this._preferences,
      initial_reading, small_tsu_okuri_as_t, keyboard_layout, keyboard_layout_overrides, input_mode_name,
      register_mode_conversions, dictionary_index, initial_okuri, keep_preedit_on_backspace)
    this._writer = buffer.Writer.new(this._buffer, line('.'), col('.'), initial_text)
    this._undo = undo.Manager.new(this._writer, revert_to_reading)
    this._view = presentation.Highlighter.new(this._writer)
    this._candidate_view = candidate_view.View.new()
    if initial_reading != ''
      if initial_text != ''
        this._Apply(this._session.StartConversion(this._entries, this._preferences))
        this._undo.MarkExistingConversion()
      else
        this._Apply([session.Result.new('', [], this._session.GetSnapshot())])
      endif
    endif
  enddef

  def _CheckTarget()
    if bufnr('%') != this._buffer || win_getid() != this._window
      throw 'caskk: editor target is not the current window and buffer'
    endif
  enddef

  def _CheckInput(allow_suspended: bool = false)
    if this._closed
      throw 'caskk: Insert-mode editor is closed'
    endif
    if this._registration_suspended && !allow_suspended
      throw 'caskk: input is suspended for dictionary registration'
    endif
    this._CheckTarget()
    if mode(1) !~# '^i'
      throw 'caskk: input requires Insert mode'
    endif
    this._undo.Check()
    const position = this._writer.GetPosition()
    if line('.') != position.line || col('.') != position.column
      throw 'caskk: cursor moved outside the tracked input position'
    endif
  enddef

  def _Apply(results: list<session.Result>): list<session.Result>
    for result in results
      this._view.Clear()
      this._undo.Apply(result)
      this._view.Render(result)
      const position = this._writer.GetPosition()
      if mode(1) =~# '^i'
        cursor(position.line, position.column)
        if line('.') != position.line || col('.') != position.column
          throw 'caskk: cannot position the Insert-mode cursor'
        endif
      else
        # InsertLeave runs after Esc has left Insert mode. Use the last
        # character, rather than the insertion point before the suffix.
        const text = getline(position.line)
        const byte = max([0, position.column - 2])
        cursor(position.line, byteidxcomp(text, charidx(text, byte, true)) + 1)
      endif
    endfor
    this._candidate_view.Render(this.GetDisplayCandidatesInfo())
    return results
  enddef

  def Feed(key: string): list<session.Result>
    this._CheckInput()
    if this.IsInCompletion()
      this.CancelCompletion()
    endif
    const results = this._session.Feed(key)
    const applied = this._Apply(results)
    if !empty(results)
      this._pending_visible = false
    endif
    this._RefreshPendingDisplay()
    return applied
  enddef

  # Keep an unfinished key visible in the tracked buffer range. It is
  # replaced by the composed kana when later input resolves the pending key.
  def _RefreshPendingDisplay()
    const pending = this._session.Pending()
    const snapshot = this._session.GetSnapshot()
    if !empty(pending)
      var text = snapshot.in_preedit ? snapshot.reading .. snapshot.okuri : ''
      for event in pending
        text ..= event.key
      endfor
      this._Apply([session.Result.new(this._session.RenderText(text), [], snapshot,
        false, false, true, false, true)])
      this._pending_visible = true
    elseif this._pending_visible
      const text = snapshot.in_preedit ? snapshot.reading .. snapshot.okuri : ''
      this._Apply([session.Result.new(this._session.RenderText(text), [], snapshot,
        !snapshot.in_preedit, false, true)])
      this._pending_visible = false
    endif
  enddef

  def GetDisplayCandidatesInfo(): conversion.CandidateListInfo
    return this._session.InCompletion() ? this._session.GetCompletionInfo()
      : this._session.GetCandidatesInfo()
  enddef

  def IsInCompletion(): bool
    return this._session.InCompletion()
  enddef

  def CreateCompletionSearch(minimum: number): completion.Search
    this._CheckInput()
    return this._session.CreateCompletionSearch(minimum)
  enddef

  def CancelCompletionSearch()
    this._session.CancelCompletionSearch()
  enddef

  def CanApplyCompletion(): bool
    if this._closed || this._registration_suspended || bufnr('%') != this._buffer
        || win_getid() != this._window || mode(1) !~# '^i' || !this.IsBufferCurrent()
      return false
    endif
    const position = this._writer.GetPosition()
    return line('.') == position.line && col('.') == position.column
  enddef

  def _PreviewCompletion()
    const info = this._session.GetCompletionInfo()
    if info is null_object
      return
    endif
    const snapshot = this._session.GetSnapshot()
    const reading = this._session.RenderText(snapshot.reading .. snapshot.okuri)
    const selected = info.selected_index >= 0
    const text = selected ? info.candidates[info.selected_index - info.candidates[0].index].text : reading
    this._Apply([session.Result.new(text, [], snapshot, false, selected, true,
      false, false, reading)])
  enddef

  def ApplyCompletion(search: completion.Search, select: bool = true): bool
    this._CheckInput()
    const shown = this._session.ApplyCompletion(search, select)
    if shown
      if select
        this._PreviewCompletion()
      else
        this._candidate_view.Render(this.GetDisplayCandidatesInfo())
      endif
    endif
    return shown
  enddef

  def MoveCompletion(delta: number)
    this._CheckInput()
    this._session.MoveCompletion(delta)
    this._PreviewCompletion()
  enddef

  def CancelCompletion()
    const preview = this.IsInCompletion()
    this._session.CancelCompletion()
    if preview
      const snapshot = this._session.GetSnapshot()
      const reading = this._session.RenderText(snapshot.reading .. snapshot.okuri)
      this._Apply([session.Result.new(reading, [], snapshot, false, false, true,
        false, false, reading)])
    endif
    this._candidate_view.Close()
  enddef

  def StartConversion(): list<session.Result>
    this._CheckInput()
    if this.IsInCompletion()
      this.CancelCompletion()
    endif
    const results = this._Apply(this._session.StartConversion(this._entries, this._preferences))
    this._pending_visible = false
    return results
  enddef

  def BackspacePending(): bool
    this._CheckInput()
    const deleted = this._session.BackspacePending()
    if deleted
      this._RefreshPendingDisplay()
    endif
    return deleted
  enddef

  def Backspace(): bool
    this._CheckInput()
    if this.IsInCompletion()
      this.CancelCompletion()
      return true
    endif
    if this._session.BackspacePending()
      this._RefreshPendingDisplay()
      return true
    endif
    const result = this._session.BackspacePreedit()
    if result is null_object
      return false
    endif
    this._Apply([result])
    return true
  enddef

  # Horizontal motion stays inside a single-line preedit. The core composes
  # input at the end, so a later input action restores the cursor to that end.
  def MoveWithinPreedit(key: string): bool
    if key !=# '<Left>' && key !=# '<Right>' || !this._session.GetSnapshot().in_preedit
        || this._session.InCandidate()
      return false
    endif
    this._CheckTarget()
    this._undo.Check()
    const range = this._writer.GetPreeditRange()
    if range is null_object || range.start.line != range.finish.line
        || line('.') != range.start.line
      return false
    endif
    const column = col('.')
    if column < range.start.column || column > range.finish.column
      return false
    endif
    const text = getline(range.start.line)
    const current = charidx(text, column - 1)
    const first = charidx(text, range.start.column - 1)
    const last = charidx(text, range.finish.column - 1)
    const target = key ==# '<Left>' ? max([first, current - 1]) : min([last, current + 1])
    if target != current
      cursor(range.start.line, byteidx(text, target) + 1)
    endif
    return true
  enddef

  def RestorePreeditCursor()
    if this._closed || !this._session.GetSnapshot().in_preedit || this._session.InCandidate()
      return
    endif
    const range = this._writer.GetPreeditRange()
    if range isnot null_object && range.start.line == range.finish.line
        && line('.') == range.start.line && col('.') >= range.start.column
        && col('.') <= range.finish.column
      cursor(range.finish.line, range.finish.column)
    endif
  enddef

  def GetRegistrationRequest(): conversion.Candidates
    if this._session.InCandidate()
      return null_object
    endif
    return this._session.GetCandidates()
  enddef

  def GetCandidates(): conversion.Candidates
    this._CheckTarget()
    return this._session.GetCandidates()
  enddef

  def Register(candidate: dictionary.Candidate): session.Result
    this._CheckInput()
    return this._Apply([this._session.Register(candidate)])[0]
  enddef

  def SuspendRegistration()
    this._CheckInput()
    if this.GetRegistrationRequest() is null_object
      throw 'caskk: no current dictionary registration request'
    endif
    this._registration_suspended = true
  enddef

  def ResumeRegistration()
    if !this._registration_suspended
      throw 'caskk: dictionary registration is not suspended'
    endif
    this._CheckInput(true)
    this._registration_suspended = false
  enddef

  # Restore the insertion point before a queued UI reply enters Insert mode.
  def PrepareRegistrationResume(): string
    if !this._registration_suspended
      throw 'caskk: dictionary registration is not suspended'
    endif
    this._CheckTarget()
    this._undo.Check()
    const insert_mode = mode(1) =~# '^i'
    if !insert_mode && mode(1) !~# '^n'
      throw 'caskk: registration return requires Normal or Insert mode'
    endif
    const position = this._writer.GetPosition()
    cursor(position.line, position.column)
    if insert_mode
      return ''
    endif
    # Normal mode clamps a position past EOL onto the final character.
    return position.column > strlen(getline(position.line)) ? 'a' : 'i'
  enddef

  def IsRegistrationSuspended(): bool
    return this._registration_suspended
  enddef

  def CancelRegistration(): session.Result
    this._CheckInput()
    return this._Apply([this._session.CancelRegistration()])[0]
  enddef

  def NextCandidate(): session.Result
    this._CheckInput()
    return this._Apply([this._session.NextCandidate()])[0]
  enddef

  def PreviousCandidate(): session.Result
    this._CheckInput()
    return this._Apply([this._session.PreviousCandidate()])[0]
  enddef

  def TogglePin()
    this._CheckInput()
    this._session.TogglePin()
    this._candidate_view.Render(this.GetDisplayCandidatesInfo())
  enddef

  def ToggleDemote()
    this._CheckInput()
    this._session.ToggleDemote()
    this._candidate_view.Render(this.GetDisplayCandidatesInfo())
  enddef

  def CanDeleteUserEntry(): bool
    this._CheckInput()
    return this._session.CanDeleteUserEntry()
  enddef

  def ShowDeleteUserEntryConfirmation(message: string)
    this._CheckInput()
    this._candidate_view.Render(this.GetDisplayCandidatesInfo(), message)
  enddef

  def DeleteUserEntry(): session.Result
    this._CheckInput()
    return this._Apply([this._session.DeleteUserEntry()])[0]
  enddef

  def Commit(): list<session.Result>
    this._CheckInput()
    const results = this._Apply(this._session.Commit())
    this._pending_visible = false
    return results
  enddef

  # May be called before Esc or by a later InsertLeave handler. Closing does not
  # require the old Insert-mode cursor position, which Esc can have adjusted.
  def Close(): list<session.Result>
    if this._closed
      return []
    endif
    this._CheckTarget()
    this._undo.Check()
    this.CancelCompletion()
    const results = this._Apply(this._session.Commit())
    this._view.Clear()
    this._undo.Close()
    this._registration_suspended = false
    this._closed = true
    return results
  enddef

  def IsClosed(): bool
    return this._closed
  enddef

  # Release presentation when the original registration window is lost.
  # No buffer edits or implicit candidate commit are allowed here.
  def Abandon()
    this._view.Clear()
    this._candidate_view.Close()
    this._registration_suspended = false
    this._closed = true
  enddef

  def GetSnapshot(): state_types.Snapshot
    return this._session.GetSnapshot()
  enddef

  def IsBufferCurrent(): bool
    return this._undo.IsCurrent()
  enddef

  def IsInCandidate(): bool
    return this._session.InCandidate()
  enddef

  def HasPendingModifier(): bool
    return this._session.HasPendingModifier()
  enddef

  def CanChangeInputMode(): bool
    return this._session.CanChangeInputMode()
  enddef

  def SetInputMode(requested: string): bool
    return this._session.SetInputMode(requested)
  enddef

  def CanCommitPreeditAsMode(requested: string): bool
    return this._session.CanCommitPreeditAsMode(requested)
  enddef

  def CommitPreeditAsMode(requested: string): list<session.Result>
    this._CheckInput()
    return this._Apply(this._session.CommitPreeditAsMode(requested))
  enddef

  def GetInputMode(): string
    return this._session.GetInputMode()
  enddef

  def Pending(): list<input.Event>
    return this._session.Pending()
  enddef

  def IsSpecialContinuation(key: string): bool
    return this._session.IsSpecialContinuation(key)
  enddef
endclass
