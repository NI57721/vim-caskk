vim9script

import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/input/mode.vim' as input_mode

export class View
  var _window: number = 0

  def new()
  enddef

  def Close()
    if this._window != 0 && !empty(popup_getpos(this._window))
      popup_close(this._window)
    endif
    this._window = 0
  enddef

  def Show(mode: string, state: string = '')
    this.Close()
    if !configuration.GetModePopup()
      return
    endif
    const labels = configuration.GetModePopupLabels()
    const markers = configuration.GetModePopupMarkers()
    const marker = get(markers, state, '')
    const label = marker .. labels[input_mode.LabelName(mode)]
    const cursor_position = screenpos(win_getid(), line('.'), col('.'))
    const position = {
      line: cursor_position.row + 1, col: cursor_position.col,
      pos: 'topleft', posinvert: true,
      padding: [0, 1, 0, 1], highlight: 'Pmenu', moved: 'any',
    }
    const timeout = configuration.GetModePopupTime()
    if timeout == 0
      this._window = popup_create(label, position)
    else
      this._window = popup_create(label, extend(copy(position), {time: timeout}))
    endif
  enddef
endclass
