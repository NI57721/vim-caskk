vim9script

import autoload 'caskk/buffer.vim' as buffer
import autoload 'caskk/session.vim' as session
import autoload 'caskk/config.vim' as configuration

const PROPERTY_TYPE = 'caskk_preedit'

# Owns only presentation properties. Clear before buffer edits and Render after
# them, so multiline edits and undo snapshots do not retain transient properties.
export class Highlighter
  const _writer: buffer.Writer
  const _buffer: number
  var _range: buffer.Range = null_object

  def new(writer: buffer.Writer)
    this._writer = writer
    this._buffer = writer.GetBufferNumber()
    configuration.ApplyHighlight()
    if empty(prop_type_get(PROPERTY_TYPE, {bufnr: this._buffer}))
      prop_type_add(PROPERTY_TYPE, {bufnr: this._buffer, highlight: 'CaskkPreedit', combine: true})
    endif
  enddef

  def Clear()
    if this._range isnot null_object && bufloaded(this._buffer)
      prop_remove({bufnr: this._buffer, type: PROPERTY_TYPE, all: true},
        this._range.start.line, this._range.finish.line)
    endif
    this._range = null_object
  enddef

  def Render(result: session.Result)
    const range = this._writer.GetPreeditRange()
    this.Clear()
    if range is null_object
      return
    endif
    if range.start.line != range.finish.line || range.start.column != range.finish.column
      prop_add(range.start.line, range.start.column, {
        bufnr: this._buffer, type: PROPERTY_TYPE,
        end_lnum: range.finish.line, end_col: range.finish.column,
      })
    endif
    if result.state.in_preedit && result.state.okuri_started && !result.in_candidate
      const reading = split(result.state.reading, "\n", true)
      const line = range.start.line + len(reading) - 1
      const column = len(reading) == 1 ? range.start.column + strlen(reading[0]) : strlen(reading[-1]) + 1
      # The boundary is decoration, never part of committed text or undo data.
      prop_add(line, column, {bufnr: this._buffer, type: PROPERTY_TYPE, text: '*'})
    endif
    this._range = range
  enddef
endclass
