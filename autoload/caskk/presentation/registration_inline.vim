vim9script

export class View
  var _window: number = 0

  def new()
  enddef

  def Show(lines: list<string>)
    if this._window != 0 && !empty(popup_getpos(this._window))
      popup_settext(this._window, lines)
      return
    endif
    this._window = popup_create(lines, {
      line: 'cursor+1', col: 'cursor', pos: 'topleft', posinvert: true,
      padding: [0, 1, 0, 1], highlight: 'Pmenu', moved: [0, 0, 0],
    })
  enddef

  def Close()
    if this._window != 0 && !empty(popup_getpos(this._window))
      popup_close(this._window)
    endif
    this._window = 0
  enddef
endclass
