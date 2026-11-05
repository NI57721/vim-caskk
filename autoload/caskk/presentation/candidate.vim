vim9script

import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/config.vim' as configuration

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

  def Render(info: conversion.CandidateListInfo)
    this.Close()
    if info is null_object || empty(info.candidates) || !configuration.GetCandidatePopup()
      return
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
    this._window = popup_create(lines, {
      line: 'cursor+1', col: 'cursor', pos: 'topleft', posinvert: true,
      padding: [0, 1, 0, 1], maxwidth: 60,
      wrap: true, highlight: 'Pmenu', moved: 'any',
    })
  enddef
endclass
