vim9script

import autoload 'caskk/session.vim' as session

# One-based line and byte column, including the position after the last byte.
export class Position
  const line: number
  const column: number

  def new(this.line, this.column)
  enddef
endclass

# Buffer integration only. The caller supplies results in their original order
# and uses GetPosition() to position the Insert-mode cursor in a later layer.
export class Writer
  const _buffer: number
  var _start_line: number
  var _start_column: number
  var _end_line: number
  var _end_column: number
  var _text: string = ''
  var _active: bool = false

  def new(number: number, line: number, column: number)
    this._buffer = number
    this._start_line = line
    this._end_line = line
    this._start_column = column
    this._end_column = column
    this._CheckPosition(line, column)
  enddef

  def _CheckPosition(line: number, column: number)
    if !bufloaded(this._buffer)
      throw 'caskk: target buffer is not loaded'
    endif
    const lines = getbufline(this._buffer, line)
    if line < 1 || empty(lines) || column < 1 || column > strlen(lines[0]) + 1
      throw 'caskk: buffer position is out of range'
    endif
    if byteidxcomp(lines[0], charidx(lines[0], column - 1, true)) != column - 1
      throw 'caskk: buffer column is not a character boundary'
    endif
  enddef

  def _CheckRange()
    this._CheckPosition(this._start_line, this._start_column)
    this._CheckPosition(this._end_line, this._end_column)
    final lines = getbufline(this._buffer, this._start_line, this._end_line)
    if len(lines) == 1
      lines[0] = strpart(lines[0], this._start_column - 1, this._end_column - this._start_column)
    else
      lines[0] = strpart(lines[0], this._start_column - 1)
      lines[-1] = strpart(lines[-1], 0, this._end_column - 1)
    endif
    if join(lines, "\n") !=# this._text
      throw 'caskk: tracked preedit text was changed externally'
    endif
  enddef

  def _Replace(text: string)
    if !getbufvar(this._buffer, '&modifiable')
      throw 'caskk: target buffer is not modifiable'
    endif
    const prefix = strpart(getbufline(this._buffer, this._start_line)[0], 0, this._start_column - 1)
    const suffix = strpart(getbufline(this._buffer, this._end_line)[0], this._end_column - 1)
    const parts = split(text, "\n", true)
    final replacement = copy(parts)
    replacement[0] = prefix .. replacement[0]
    replacement[-1] ..= suffix
    setbufline(this._buffer, this._start_line, replacement[0])
    if this._end_line > this._start_line
      deletebufline(this._buffer, this._start_line + 1, this._end_line)
    endif
    if len(replacement) > 1
      appendbufline(this._buffer, this._start_line, replacement[1 :])
    endif
    this._end_line = this._start_line + len(parts) - 1
    this._end_column = len(parts) == 1 ? this._start_column + strlen(parts[0]) : strlen(parts[-1]) + 1
    this._text = text
  enddef

  def _Finish()
    this._start_line = this._end_line
    this._start_column = this._end_column
    this._text = ''
    this._active = false
  enddef

  def Apply(result: session.Result)
    if !empty(result.unhandled)
      return
    endif
    this._CheckRange()
    if result.commit_preedit
      if result.replace_preedit
        this._Replace(result.text)
      elseif result.text !=# this._text
        throw 'caskk: commit text does not match tracked preedit'
      endif
      this._Finish()
    elseif result.replace_preedit
      this._Replace(result.text)
      this._active = true
    elseif result.state.in_preedit
      this._Replace(result.state.reading .. result.state.okuri)
      this._active = true
    elseif result.text != ''
      this._Replace(result.text)
      this._Finish()
    endif
  enddef

  def InPreedit(): bool
    return this._active
  enddef

  def GetPosition(): Position
    return Position.new(this._end_line, this._end_column)
  enddef
endclass
