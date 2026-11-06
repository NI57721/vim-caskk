vim9script

import autoload 'caskk/session.vim' as session
import autoload 'caskk/input/mode.vim' as input_mode
import autoload 'caskk/conversion.vim' as conversion

# Buffer-independent registration text and the composition inserted at its cursor.
export class Editor
  const input: session.Session
  var _text: string = ''
  var _cursor: number = 0

  def new(this.input)
  enddef

  def GetText(): string
    return this._text
  enddef

  def GetCursor(): number
    return this._cursor
  enddef

  def Prefix(): string
    return strcharpart(this._text, 0, this._cursor)
  enddef

  def Suffix(): string
    return strcharpart(this._text, this._cursor)
  enddef

  def InsertLiteral(text: string)
    this._text = this.Prefix() .. text .. this.Suffix()
    this._cursor += strchars(text)
  enddef

  def Append(results: list<session.Result>)
    for result in results
      if result.commit_preedit || (!result.in_candidate && !result.state.in_preedit && result.text !=# '')
        this.InsertLiteral(result.text)
      endif
    endfor
  enddef

  def Commit()
    if this.input.InCandidate() || this.input.GetSnapshot().in_preedit
        || !empty(this.input.Pending())
      this.Append(this.input.Commit())
    endif
  enddef

  def Move(offset: number)
    this.Commit()
    this._cursor = max([0, min([strchars(this._text), this._cursor + offset])])
  enddef

  def Delete(before: bool)
    this.Commit()
    const index = before ? this._cursor - 1 : this._cursor
    if index < 0 || index >= strchars(this._text)
      return
    endif
    this._text = strcharpart(this._text, 0, index) .. strcharpart(this._text, index + 1)
    if before
      this._cursor -= 1
    endif
  enddef

  def Paste(text: string)
    this.Commit()
    this.InsertLiteral(text)
  enddef

  def Candidates(): conversion.CandidateListInfo
    return this.input.GetCandidatesInfo()
  enddef

  def Insertion(): string
    if this.input.InCandidate()
      const info = this.Candidates()
      return empty(info.candidates) ? '' : info.candidates[info.selected_index].text
    endif
    const snapshot = this.input.GetSnapshot()
    var insertion = snapshot.in_preedit
      ? input_mode.Render(snapshot.reading .. snapshot.okuri, this.input.GetInputMode()) : ''
    for event in this.input.Pending()
      insertion ..= event.key
    endfor
    return insertion
  enddef

  def Highlighted(): bool
    return this.input.InCandidate() || this.input.GetSnapshot().in_preedit
  enddef

  def Marker(): string
    return this.input.InCandidate() ? 'candidate' : this.input.GetSnapshot().in_preedit ? 'modified' : ''
  enddef
endclass
