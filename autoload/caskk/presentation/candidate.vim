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

  def Render(info: conversion.CandidateInfo)
    this.Close()
    if info is null_object || !configuration.GetCandidatePopup()
      return
    endif
    const marker = info.tier ==# 'pinned' ? '★ ' : info.tier ==# 'demoted' ? '↓ ' : ''
    final lines = [(info.index + 1) .. '/' .. info.count .. ' ' .. marker .. info.text]
    for annotation in info.annotations
      lines->extend(split(annotation, "\n", true))
    endfor
    this._window = popup_create(lines, {
      line: 'cursor+1', col: 'cursor', pos: 'topleft', posinvert: true,
      padding: [0, 1, 0, 1], maxwidth: 60, maxheight: 6,
      wrap: true, highlight: 'Pmenu', moved: 'any',
    })
  enddef
endclass
