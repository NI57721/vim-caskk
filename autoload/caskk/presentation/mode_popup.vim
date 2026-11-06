vim9script

import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/input/mode.vim' as input_mode

# Screen row immediately above the command cursor, and its display column.
export def CommandlineAnchor(): list<number>
  const prefix = strpart(getcmdline(), 0, max([0, getcmdpos() - 1]))
  const cells = strdisplaywidth(prefix, 1) + 1
  const total = strdisplaywidth(getcmdline(), 1) + 1
  const rows = total / &columns
  return [max([1, &lines - max([&cmdheight, rows + 1]) + cells / &columns]),
    cells % &columns + 1]
enddef

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

  def ShowCommandline(mode: string, state: string = '')
    this.Show(mode, state, true)
  enddef

  def Show(mode: string, state: string = '', commandline: bool = false, screen_anchor: list<number> = [])
    this.Close()
    if !configuration.GetModePopup()
      return
    endif
    const labels = configuration.GetModePopupLabels()
    const markers = configuration.GetModePopupMarkers()
    const marker = get(markers, state, '')
    const label = marker .. labels[input_mode.LabelName(mode)]
    const cursor_position = screenpos(win_getid(), line('.'), col('.'))
    const anchor = commandline ? CommandlineAnchor() : [0, 0]
    final position = {
      line: commandline ? anchor[0] : cursor_position.row + 1,
      col: commandline ? anchor[1] : cursor_position.col,
      pos: 'topleft', posinvert: true,
      padding: [0, 1, 0, 1], highlight: 'Pmenu', moved: [0, 0, 0],
    }
    if !empty(screen_anchor)
      position.line = screen_anchor[0]
      position.col = screen_anchor[1]
    endif
    if commandline
      remove(position, 'moved')
    endif
    const timeout = configuration.GetModePopupTime()
    if timeout == 0
      this._window = popup_create(label, position)
    else
      this._window = popup_create(label, extend(copy(position), {time: timeout}))
    endif
  enddef
endclass
