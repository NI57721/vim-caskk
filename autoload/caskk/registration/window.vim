vim9script

import 'caskk/registration.vim' as registration

# Window ownership and presentation only; IME input belongs to Binding/Editor.
export class Window
  const origin_window: number
  const origin_buffer: number
  const window: number
  const buffer: number
  const event_group: string
  const origin_bufhidden: string
  const previous_statusline: string
  const previous_winfixheight: bool

  def new(this.origin_window, this.origin_buffer, this.window, this.buffer, this.origin_bufhidden,
      this.previous_statusline, this.previous_winfixheight)
    this.event_group = 'caskk_registration_' .. this.buffer
  enddef

  def Message(text: string)
    if win_id2win(this.window) > 0
      setwinvar(this.window, '&statusline', substitute(text, '%', '%%', 'g'))
    endif
  enddef

  # False means the original Editor's window/buffer no longer exists.
  def Close(): bool
    const returned = win_gotoid(this.origin_window) != 0 && bufexists(this.origin_buffer)
    if returned
      execute 'keepalt hide buffer ' .. this.origin_buffer
    elseif bufnr('%') == this.buffer
      if bufexists(this.origin_buffer)
        execute 'keepalt hide buffer ' .. this.origin_buffer
      else
        enew
      endif
    endif
    if win_id2win(this.window) > 0 && this.window != win_getid()
      win_execute(this.window, 'close!')
    elseif win_getid() == this.window && bufnr('%') == this.buffer
      enew
    endif
    if bufexists(this.buffer)
      execute 'silent! bwipeout! ' .. this.buffer
    endif
    if bufexists(this.origin_buffer) && getbufvar(this.origin_buffer, '&bufhidden') ==# 'hide'
      setbufvar(this.origin_buffer, '&bufhidden', this.origin_bufhidden)
    endif
    if win_id2win(this.window) > 0 && this.window == win_getid()
      &l:statusline = this.previous_statusline
      &l:winfixheight = this.previous_winfixheight
    endif
    return returned
  enddef
endclass

export def Open(request: registration.Request): Window
  const origin_window = win_getid()
  const origin_buffer = bufnr('%')
  const origin_bufhidden: string = getbufvar(origin_buffer, '&bufhidden')
  const statusline = &l:statusline
  const fixed_height = &l:winfixheight
  setbufvar(origin_buffer, '&bufhidden', 'hide')
  var window: Window = null_object
  try
    botright :3new
    window = Window.new(origin_window, origin_buffer, win_getid(), bufnr('%'), origin_bufhidden,
      statusline, fixed_height)
    setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted winfixheight
    const suffix = request.okuri == '' ? '' : '*' .. request.okuri
    window.Message('辞書登録: ' .. request.reading .. suffix .. '  [Enter:登録 Esc:取消]')
  catch
    const reason = v:exception
    if window isnot null_object
      window.Close()
    else
      setbufvar(origin_buffer, '&bufhidden', origin_bufhidden)
      win_gotoid(origin_window)
    endif
    throw 'caskk: cannot create registration window: ' .. reason
  endtry
  return window
enddef
