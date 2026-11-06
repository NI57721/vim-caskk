vim9script

import autoload 'caskk/buffer.vim' as buffer
import autoload 'caskk/session.vim' as session
import autoload 'caskk/state.vim' as state_types

export class Manager
  const _writer: buffer.Writer
  const _buffer: number
  const _revert_to_reading: bool
  var _tick: number
  var _unit_open: bool = false
  var _preedit: bool = false
  var _pending_display: bool = false
  var _reading_state: state_types.Snapshot = null_object
  var _reading_display: string = ''
  var _existing_conversion: bool = false

  def new(writer: buffer.Writer, revert_to_reading: bool = true)
    this._writer = writer
    this._buffer = writer.GetBufferNumber()
    this._revert_to_reading = revert_to_reading
    this._CheckTarget()
    this._tick = getbufvar(this._buffer, 'changedtick')
  enddef

  def _CheckTarget()
    if bufnr('%') != this._buffer
      throw 'caskk: undo target must be the current buffer'
    endif
  enddef

  def _Break()
    # :help undo-break documents this as closing a block while preserving
    # both global and buffer-local undolevels values.
    &g:undolevels = &g:undolevels
    this._unit_open = false
  enddef

  def _Write(result: session.Result)
    const preedit = result.state.in_preedit && !result.commit_preedit
    const changes_text = result.replace_preedit || preedit || (!result.commit_preedit && result.text != '')
    if changes_text
      if !this._unit_open || (preedit && !this._preedit && !this._pending_display)
        this._Break()
      else
        undojoin
      endif
    endif
    this._writer.Apply(result)
    const tick: number = getbufvar(this._buffer, 'changedtick')
    if tick != this._tick
      this._unit_open = true
    endif
    this._tick = tick
    this._preedit = preedit
    this._pending_display = result.pending_display
  enddef

  # Also used before core input is consumed by the Insert-mode integration.
  def IsCurrent(): bool
    return getbufvar(this._buffer, 'changedtick') == this._tick
  enddef

  def Check()
    this._CheckTarget()
    if getbufvar(this._buffer, 'changedtick') != this._tick
      throw 'caskk: buffer changed outside the managed undo unit'
    endif
  enddef

  def Apply(result: session.Result)
    this.Check()
    if !empty(result.unhandled)
      return
    endif
    if result.commit_preedit && this._revert_to_reading && !this._existing_conversion
        && this._reading_state isnot null_object
        && result.text !=# (this._reading_state.reading .. this._reading_state.okuri)
      # Finish the composition's existing undo block as plain reading text.
      # Only the final committed candidate gets a separate block; browsing
      # candidates never leaves intermediate selections in the undo history.
      const reading = this._reading_display != '' ? this._reading_display
        : this._reading_state.reading .. this._reading_state.okuri
      this._Write(session.Result.new(reading, [], this._reading_state, false, false, true))
      this._Break()
      this._Write(session.Result.new(result.text, result.unhandled, result.state,
        result.commit_preedit, result.in_candidate, true, result.registration_requested))
    else
      this._Write(result)
    endif
    if result.commit_preedit
      this.Close()
    elseif result.state.in_preedit && !this._existing_conversion
      this._reading_state = result.state
      this._reading_display = result.preedit_text
    endif
  enddef

  # The integration layer also calls this when Insert-mode input ends.
  def Close()
    this._CheckTarget()
    this._Break()
    this._preedit = false
    this._pending_display = false
    this._reading_state = null_object
    this._reading_display = ''
    this._existing_conversion = false
    this._tick = getbufvar(this._buffer, 'changedtick')
  enddef

  # A reconversion replaces confirmed text directly with its selected
  # candidate.  The existing buffer text is the undo origin, so committing
  # that candidate must not first create an intermediate reading undo unit.
  def MarkExistingConversion()
    this._reading_state = null_object
    this._reading_display = ''
    this._existing_conversion = true
  enddef
endclass
