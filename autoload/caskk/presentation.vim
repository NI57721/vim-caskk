vim9script

import autoload 'caskk/buffer.vim' as buffer

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
    highlight default CaskkPreedit term=underline cterm=underline gui=underline
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

  def Render()
    const range = this._writer.GetPreeditRange()
    this.Clear()
    if range is null_object || (range.start.line == range.finish.line && range.start.column == range.finish.column)
      return
    endif
    prop_add(range.start.line, range.start.column, {
      bufnr: this._buffer, type: PROPERTY_TYPE,
      end_lnum: range.finish.line, end_col: range.finish.column,
    })
    this._range = range
  enddef
endclass
