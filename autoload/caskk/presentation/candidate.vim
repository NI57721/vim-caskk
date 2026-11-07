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
    const tier = candidate.tier ==# 'pinned' ? '★ ' : candidate.tier ==# 'demoted' ? '↓ ' : ''
    var line = (candidate.index + 1) .. '/' .. candidate.count .. ' ' .. tier .. candidate.text
    if !empty(candidate.annotations)
      const annotation = substitute(join(candidate.annotations, ' / '), "\n", ' ', 'g')
      line ..= ' — ' .. annotation
    endif
    lines->add(line)
  endfor
  return lines
enddef

# Highlight the selected buffer line without moving either window's cursor.
export def HighlightSelection(window: number, line: number)
  const buffer = winbufnr(window)
  const type = 'caskk_candidate_selected'
  if empty(prop_type_get(type, {bufnr: buffer}))
    prop_type_add(type, {bufnr: buffer, highlight: 'PmenuSel', combine: false})
  else
    prop_remove({bufnr: buffer, type: type, all: true}, 1, len(getbufline(buffer, 1, '$')))
  endif
  if line > 0
    prop_add(line, 1, {bufnr: buffer, type: type, length: strlen(getbufline(buffer, line)[0])})
  endif
enddef

# A read-only information popup. Input and selection stay in the source window.
export class View
  var _window: number = 0
  var _confirmation: bool = false

  def new()
  enddef

  def Close()
    if this._window != 0 && !empty(popup_getpos(this._window))
      popup_close(this._window)
    endif
    this._window = 0
    this._confirmation = false
  enddef

  def Render(info: conversion.CandidateListInfo, message: string = '', commandline: bool = false)
    if info is null_object || empty(info.candidates) || !configuration.GetCandidatePopup()
      this.Close()
      return
    endif
    if message !=# ''
      # A confirmation must not inherit the candidate list's fixed viewport.
      this.Close()
      this._window = popup_create([message], {
        pos: 'center', padding: [0, 1, 0, 1],
        maxwidth: min([60, max([1, &columns - 2])]),
        wrap: true, highlight: 'Pmenu', moved: 'any',
      })
      this._confirmation = true
      return
    elseif this._confirmation
      this.Close()
    endif
    const lines = Format(info)
    const previous = this._window == 0 ? {} : popup_getpos(this._window)
    if !empty(previous)
      # Preserve the initial screen rectangle as selection scrolls toward the end.
      popup_settext(this._window, lines)
      popup_setoptions(this._window, {
        line: previous.line, col: previous.col, pos: 'topleft', posinvert: false,
        minheight: previous.core_height, maxheight: previous.core_height,
        minwidth: previous.core_width, maxwidth: previous.core_width,
        firstline: max([1, info.selected_index - info.candidates[0].index + 1]),
      })
      if !commandline
        # Candidate replacement may move the buffer cursor; track its new position.
        popup_setoptions(this._window, {moved: 'any'})
      endif
      HighlightSelection(this._window, info.selected_index - info.candidates[0].index + 1)
      return
    endif
    final position: dict<any> = {
      line: 'cursor+1', col: 'cursor', pos: 'topleft', posinvert: true,
      firstline: max([1, info.selected_index - info.candidates[0].index + 1]),
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
    HighlightSelection(this._window, info.selected_index - info.candidates[0].index + 1)
  enddef
endclass
