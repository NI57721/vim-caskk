vim9script

import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/registration/editor.vim' as registration_editor
import autoload 'caskk/presentation/candidate.vim' as candidate_view
import 'caskk/registration.vim' as registration

const PROPERTY_TYPE = 'caskk_preedit'

export class View
  var _window: number = 0
  var _line: number = 0
  var _col: number = 0

  def new()
  enddef

  def ShowEditor(request: registration.Request, editor: registration_editor.Editor, message: string = '', annotation_lines: list<string> = [])
    const header = request is null_object ? '辞書登録'
      : '辞書登録: ' .. request.reading .. (request.okuri == '' ? '' : '*' .. request.okuri)
    final lines = [header .. '  [Enter:登録 Esc:取消]']
    var selected_line = 0
    const prefix = editor.Prefix()
    const insertion = editor.Insertion()
    lines->add('登録語: ' .. prefix .. insertion .. '│' .. editor.Suffix())
    if !empty(annotation_lines)
      lines->extend(annotation_lines)
    elseif message !=# ''
      lines->add(message)
    elseif editor.input.InCandidate()
      const info = editor.Candidates()
      const candidates = candidate_view.Format(info)
      const visible = 6
      if len(candidates) <= visible
        selected_line = len(lines) + info.selected_index + 1
        lines->extend(candidates)
      else
        const start = max([0, min([info.selected_index - 2, len(candidates) - visible])])
        if start > 0
          lines->add('…')
        endif
        selected_line = len(lines) + info.selected_index - start + 1
        lines->extend(candidates[start : start + visible - 1])
        if start + visible < len(candidates)
          lines->add('…')
        endif
      endif
    endif
    const highlight_start = editor.Highlighted() && insertion !=# ''
      ? strlen('登録語: ' .. prefix) + 1 : 0
    this.Show(lines, highlight_start, strlen(insertion), selected_line)
  enddef

  def Show(lines: list<string>, highlight_start: number = 0, highlight_length: number = 0, selected_line: number = 0)
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
    candidate_view.HighlightSelection(this._window, selected_line)
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

  def ModeAnchor(): list<number>
    const position = popup_getpos(this._window)
    return [position.line + position.height, position.col]
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
