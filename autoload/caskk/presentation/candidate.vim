vim9script

import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/input/mapping.vim' as mapping

export def PageKeys(inline: bool = false): list<string>
  const keys = configuration.GetCandidateSelectKeys()
  # Reserve one unwrapped line for the rank prompt, plus the inline editor's
  # two header lines when it shares the candidate popup.
  const available = inline ? min([10, &lines - &cmdheight]) - 3 : &lines - &cmdheight - 1
  return available <= 0 ? [] : keys[: available - 1]
enddef

# Leave the wrapped command line and its end cursor below the popup.
def CommandlineRoom(): number
  var row = 1
  var column = 1
  for char in split(getcmdline(), '\zs')
    const width = strdisplaywidth(char, column)
    if column + width > &columns
      row += 1
      column = 0
    endif
    column += width
  endfor
  return &lines - max([&cmdheight, row + column / &columns])
enddef

def CommandlineWidth(): number
  return min([60, &columns - 2])
enddef

def RankPrompt(action: string): string
  const operation = action ==# 'TogglePin' ? '固定' : '降格'
  return operation .. 'する候補のラベルを入力（Escで取消）'
enddef

def CommandlinePrompt(action: string): list<string>
  const width = CommandlineWidth()
  final rows: list<string> = ['']
  for char in split(RankPrompt(action), '\zs')
    if strdisplaywidth(rows[-1] .. char) > width
      rows->add('')
    endif
    rows[-1] ..= char
  endfor
  return rows
enddef

export def CommandlinePageKeys(excluded: string): list<string>
  if CommandlineWidth() < 4
    return []
  endif
  const available = CommandlineRoom() - len(CommandlinePrompt('TogglePin'))
  if available <= 0
    return []
  endif
  return configuration.GetCandidateSelectKeys()
    ->filter((_, key) => mapping.Lhs(key) !=# excluded)[: available - 1]
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
    const label = empty(keys) ? '' : keys[candidate.index - start] .. ' '
    var line = label .. tier .. candidate.text
    if !empty(candidate.annotations)
      const annotation = substitute(join(candidate.annotations, ' / '), "\n", ' ', 'g')
      line ..= ' — ' .. annotation
    endif
    lines->add(line)
  endfor
  if !empty(keys) && rank_action !=# ''
    lines->add(RankPrompt(rank_action))
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

# Keep the selection within the first three rows, or fewer in a short popup.
def FirstCandidateLine(selected: number, height: number): number
  const selection_rows = min([3, max([1, height])])
  return max([1, selected - selection_rows + 1])
enddef

# Count screen rows before the selected candidate, including wrapped text.
def WrappedRows(text: string, width: number): number
  if strdisplaywidth(text) <= width
    return 1
  endif
  var cells = 0
  for char in split(text, '\zs')
    const size = strdisplaywidth(char, cells)
    const column = cells % width
    if size == 2 && column == width - 1 && char !=# "\t" && width > 1
      cells += 1
    endif
    cells += size
  endfor
  return max([1, (cells + width - 1) / width])
enddef

def FitWrappedSelection(lines: list<string>, first: number, selected: number, viewport: dict<number>): number
  const width = max([1, viewport.core_width])
  var remaining = viewport.core_height - 1
  var top = selected
  while top > first
    remaining -= WrappedRows(lines[top - 2], width)
    if remaining < 0
      break
    endif
    top -= 1
  endwhile
  return top
enddef

# A read-only information popup. Input and selection stay in the source window.
export class View
  var _window: number = 0
  var _confirmation: bool = false
  var _labelled_above: bool = false

  def new()
  enddef

  def Close()
    if this._window != 0 && !empty(popup_getpos(this._window))
      popup_close(this._window)
    endif
    this._window = 0
    this._confirmation = false
  enddef

  def RenderCommandline(info: conversion.CandidateListInfo, keys: list<string>, rank_action: string)
    const room = CommandlineRoom()
    const width = CommandlineWidth()
    if info is null_object || room <= 0 || width <= 0 || !configuration.GetCandidatePopup()
      this.Close()
      return
    endif
    final lines = Format(info, keys)
    if !empty(keys) && rank_action !=# ''
      lines->extend(CommandlinePrompt(rank_action))
    endif
    const unlabelled = empty(keys)
    const previous = this._window == 0 ? {} : popup_getpos(this._window)
    const height = min([room, len(lines)])
    const selected = info.selected_index + 1
    # Vim scrolls the popup with the screen when the command line wraps.
    const options = {
      line: &lines - &cmdheight, col: 1, pos: 'botleft', posinvert: false,
      maxheight: room, maxwidth: width, wrap: false,
      padding: [0, 1, 0, 1], highlight: 'Pmenu',
      minheight: unlabelled ? height : 0,
      firstline: unlabelled ? FirstCandidateLine(selected, height) : 1,
    }
    if empty(previous)
      this._window = popup_create(lines, options)
    else
      popup_settext(this._window, lines)
      popup_setoptions(this._window, options)
    endif
    HighlightSelection(this._window, unlabelled ? selected : 0)
  enddef

  def Render(info: conversion.CandidateListInfo, message: string = '',
      keys: list<string> = [], rank_action: string = '', scroll_candidates: bool = false)
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
      const previous = this._window == 0 ? {} : popup_getpos(this._window)
      const anchor = screenpos(win_getid(), line('.'), col('.'))
      this._labelled_above = (!empty(previous) && this._labelled_above)
        || anchor.row + len(lines) > &lines - &cmdheight
      const top = this._labelled_above ? max([1, anchor.row - len(lines)]) : anchor.row + 1
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
      const page_start = conversion.PageStart(info.selected_index, len(keys))
      HighlightSelection(this._window, info.selected_index - page_start + 1)
      return
    endif
    this._labelled_above = false
    const previous = this._window == 0 ? {} : popup_getpos(this._window)
    const selected = info.selected_index - info.candidates[0].index + 1
    if empty(previous)
      this._window = popup_create(lines, {
        line: 'cursor+1', col: 'cursor', pos: 'topleft', posinvert: true,
        firstline: scroll_candidates ? 1 : selected,
        padding: [0, 1, 0, 1], maxwidth: 60,
        wrap: true, highlight: 'Pmenu', moved: 'any',
      })
    else
      popup_settext(this._window, lines)
    endif
    const viewport = empty(previous) ? popup_getpos(this._window) : previous
    var top = selected
    if scroll_candidates
      top = FirstCandidateLine(selected, viewport.core_height)
      top = FitWrappedSelection(lines, top, selected, viewport)
    endif
    if !empty(previous) || (scroll_candidates && selected > 1)
      # Preserve the initial screen rectangle as the list scrolls.
      popup_setoptions(this._window, {
        line: viewport.line, col: viewport.col, pos: 'topleft', posinvert: false,
        minheight: viewport.core_height, maxheight: viewport.core_height,
        minwidth: viewport.core_width, maxwidth: viewport.core_width, firstline: top,
      })
    endif
    # Candidate replacement may move the buffer cursor; track its new position.
    if !empty(previous)
      popup_setoptions(this._window, {moved: 'any'})
    endif
    HighlightSelection(this._window, selected)
  enddef
endclass
