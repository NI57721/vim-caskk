vim9script
import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state/runtime.vim' as runtime
const suite = themis#suite('experimental candidate buffer text')
const assert = themis#helper('assert')
var captured = ''
var rows: list<string> = []
def Capture()
  captured = getline(1)
  rows = []
  for window in popup_list()
    rows->extend(getbufline(winbufnr(window), 1, '$'))
  endfor
enddef
suite.popup_keeps_marker_while_buffer_shows_only_candidate = (): void => {
  const previous = bufnr('%')
  const snapshot = runtime.Get().GetSnapshot()
  const path = tempname()
  writefile(['か /書;@verb-5-k/描;@verb-5-k/'], path)
  enew
  setlocal buftype=nofile noswapfile
  const number = bufnr('%')
  try
    Caskk.RegisterInputScheme({name: 'marker', consonants: {k: 'k'}, combinations: {a: 'a', u: 'u'}})
    Caskk.Config({dictionaries: [path], mappings: {"\<Space>": 'NextCandidate'}})
    Caskk.Enable('marker')
    inoremap <buffer> <F12> <ScriptCmd>Capture()<CR>
    feedkeys("iKaKu\<Space>\<F12>\<Esc>", 'xt')
    assert.equals(captured, '描く')
    assert.equals(getline(1), '描く')
    assert.equals(len(filter(copy(rows), (_, row) => row =~# '描く［verb］')) > 0, true)
  finally
    Caskk.Disable()
    Caskk.Config({})
    runtime.Get().Restore(snapshot)
    execute 'noautocmd keepalt hide buffer ' .. previous
    execute 'silent! bwipeout! ' .. number
    delete(path)
  endtry
}
