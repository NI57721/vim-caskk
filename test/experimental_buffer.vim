vim9script
import autoload 'caskk.vim' as Caskk
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
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


suite.backspace_delete_actions_confirm_and_remove_registered_stems = (): void => {
  for key in ["\<BS>", "\<C-H>"]
    const previous = bufnr('%')
    const snapshot = runtime.Get().GetSnapshot()
    enew
    setlocal buftype=nofile noswapfile
    const number = bufnr('%')
    try
      Caskk.RegisterInputScheme({name: 'delete-stem', consonants: {k: 'k'}, combinations: {a: 'a', u: 'u'}})
      Caskk.Config({registration_auto: false, mappings: {
        "\<BS>": 'DeleteUserEntry', "\<C-H>": 'DeleteUserEntry'}})
      runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('書', ['@verb-5-k']))
      Caskk.Enable('delete-stem')
      inoremap <buffer> <F12> <ScriptCmd>Capture()<CR>
      feedkeys("iKaKu" .. key .. "\<F12>n" .. key .. "y\<Esc>", 'xt')
      assert.equals(captured, '書く')
      assert.equals(len(filter(copy(rows), (_, row) => row =~# 'ユーザー辞書から削除')), 1)
      assert.equals(getline(1), 'かく')
      assert.equals(runtime.Get().HasEntryForLookup(lookup.CreateQuery('か', ''), '書'), false)
    finally
      Caskk.Disable()
      Caskk.Config({})
      runtime.Get().Restore(snapshot)
      execute 'noautocmd keepalt hide buffer ' .. previous
      execute 'silent! bwipeout! ' .. number
    endtry
  endfor
}
