vim9script

import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/presentation/mode_popup.vim' as mode_popup

export def Format(info: conversion.CandidateListInfo): list<string>
  if info is null_object
    return []
  endif
  final lines: list<string> = []
  for candidate in info.candidates
    const selected = candidate.index == info.selected_index ? '▶ ' : '  '
    const tier = candidate.tier ==# 'pinned' ? '★ ' : candidate.tier ==# 'demoted' ? '↓ ' : ''
    var line = selected .. (candidate.index + 1) .. '/' .. candidate.count .. ' ' .. tier .. candidate.text
    if !empty(candidate.annotations)
      const annotation = substitute(join(candidate.annotations, ' / '), "\n", ' ', 'g')
      line ..= ' — ' .. annotation
    endif
    lines->add(line)
  endfor
  return lines
enddef

# A read-only information popup. Input and selection stay in the source window.
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

  def Render(info: conversion.CandidateListInfo, message: string = '', commandline: bool = false)
    this.Close()
    if info is null_object || empty(info.candidates) || !configuration.GetCandidatePopup()
      return
    endif
    var lines = Format(info)
    if message !=# ''
      lines->add(message)
    endif
    final position: dict<any> = {
      line: 'cursor+1', col: 'cursor', pos: 'topleft', posinvert: true,
      firstline: info.selected_index + 1,
      padding: [0, 1, 0, 1], maxwidth: 60,
      wrap: true, highlight: 'Pmenu', moved: 'any',
    }
    if commandline
      const anchor = mode_popup.CommandlineAnchor()
      position.line = max([1, anchor[0] - 1])
      position.col = anchor[1]
      position.pos = 'botleft'
      position.maxheight = max([1, anchor[0] - 1])
      remove(position, 'moved')
    endif
    this._window = popup_create(lines, position)
  enddef
endclass
