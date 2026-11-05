vim9script

import autoload 'caskk/config.vim' as configuration

const PROPERTY_TYPE = 'caskk_preedit'

export class View
  var _window: number = 0
  var _line: number = 0
  var _col: number = 0

  def new()
  enddef

  def Show(lines: list<string>, highlight_start: number = 0, highlight_length: number = 0)
    if this._window != 0 && !empty(popup_getpos(this._window))
      # Keep later text growth and candidate-list changes at the initial screen
      # coordinates instead of resolving the cursor-relative anchor again.
      popup_setoptions(this._window, {
        line: this._line, col: this._col, pos: 'topleft', posinvert: false,
      })
      popup_settext(this._window, lines)
    else
      this._window = popup_create(lines, {
        line: 'cursor-1', col: 'cursor', pos: 'botleft', posinvert: true,
        padding: [0, 1, 0, 1], maxheight: 10, maxwidth: 60,
        highlight: 'Pmenu', moved: [0, 0, 0],
      })
      const position = popup_getpos(this._window)
      this._line = position.line
      this._col = position.col
    endif
    const buffer = winbufnr(this._window)
    if !empty(prop_type_get(PROPERTY_TYPE, {bufnr: buffer}))
      prop_remove({bufnr: buffer, type: PROPERTY_TYPE, all: true}, 1, len(getbufline(buffer, 1, '$')))
    else
      prop_type_add(PROPERTY_TYPE, {bufnr: buffer, highlight: 'CaskkPreedit', combine: true})
    endif
    if highlight_start > 0 && highlight_length > 0
      configuration.ApplyHighlight()
      prop_add(2, highlight_start, {
        bufnr: buffer, type: PROPERTY_TYPE, length: highlight_length,
      })
    endif
  enddef

  def Close()
    if this._window != 0 && !empty(popup_getpos(this._window))
      popup_close(this._window)
    endif
    this._window = 0
    this._line = 0
    this._col = 0
  enddef
endclass
