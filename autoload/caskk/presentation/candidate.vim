vim9script

import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/presentation/mode_popup.vim' as mode_popup

export def PageKeys(inline: bool = false): list<string>
  const keys = configuration.GetCandidateSelectKeys()
  # Reserve one unwrapped line for the rank prompt, plus the inline editor's
  # two header lines when it shares the candidate popup.
  const available = inline ? min([10, &lines - &cmdheight]) - 3 : &lines - &cmdheight - 1
  return available <= 0 ? [] : keys[: available - 1]
enddef

export def Format(info: conversion.CandidateListInfo, keys: list<string> = [], rank_action: string = ''): list<string>
  if info is null_object
    return []
  endif
  final lines: list<string> = []
  const start = empty(keys) ? 0 : conversion.PageStart(info.selected_index, len(keys))
  const candidates = empty(keys) ? info.candidates : info.candidates[start : start + len(keys) - 1]
  for candidate in candidates
    const tier = candidate.tier ==# 'pinned' ? '★ ' : candidate.tier ==# 'demoted' ? '↓ ' : ''
    const label = empty(keys) ? (candidate.index + 1) .. '/' .. candidate.count : keys[candidate.index - start]
    var line = label .. ' ' .. tier .. candidate.text
    if !empty(candidate.annotations)
      const annotation = substitute(join(candidate.annotations, ' / '), "\n", ' ', 'g')
      line ..= ' — ' .. annotation
    endif
    lines->add(line)
  endfor
  if !empty(keys) && rank_action !=# ''
    const operation = rank_action ==# 'TogglePin' ? '固定' : '降格'
    lines->add(operation .. 'する候補のラベルを入力（Escで取消）')
  endif
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

  def Render(info: conversion.CandidateListInfo, message: string = '', commandline: bool = false,
      keys: list<string> = [], rank_action: string = '')
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
    const lines = Format(info, keys, rank_action)
    if !empty(keys)
      const selected = info.selected_index - conversion.PageStart(info.selected_index, len(keys)) + 1
      const previous = this._window == 0 ? {} : popup_getpos(this._window)
      const last_top = max([1, &lines - &cmdheight - len(keys)])
      const anchor = screenpos(win_getid(), line('.'), col('.'))
      const below = anchor.row + 1
      const initial = below <= last_top ? below : max([1, anchor.row - len(keys) - 1])
      const top = min([get(previous, 'line', initial), last_top])
      const width = min([60, max(mapnew(lines, (_, line) => strdisplaywidth(line)))]) + 2
      const left = min([max([1, get(previous, 'col', anchor.col)]), max([1, &columns - width + 1])])
      const options = {
        line: top, col: left, pos: 'topleft', posinvert: false, firstline: 1,
        minheight: 0, maxheight: 0, minwidth: 0,
        padding: [0, 1, 0, 1], maxwidth: 60, wrap: false, highlight: 'Pmenu',
        moved: 'any',
      }
      if empty(previous)
        this._window = popup_create(lines, options)
      else
        popup_setoptions(this._window, options)
        popup_settext(this._window, lines)
      endif
      HighlightSelection(this._window, selected)
      return
    endif
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
