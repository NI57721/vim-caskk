vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('Normal-mode reconversion')
const assert = themis#helper('assert')

class Fixture
  const previous: number
  const buffer: number
  const directory: string
  const existing_popups: list<number>
  const snapshot: user_state.Snapshot

  def new(this.previous, this.buffer, this.directory, this.existing_popups, this.snapshot)
  enddef
endclass

def Setup(): Fixture
  const previous = bufnr('%')
  const snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  nnoremap <buffer> <silent> <C-N> 2j
  const directory = tempname()
  mkdir(directory)
  writefile(['か /蚊/科/', 'かk /書/'], directory .. '/system')
  Caskk.RegisterInputScheme({name: 'reconversion', consonants: {k: 'k'}, combinations: {a: 'a', u: 'u'}})
  Caskk.Config({dictionaries: [directory .. '/system'], candidate_popup: true, mode_popup: false,
    mappings: {s: 'Convert', c: 'Commit'}})
  Caskk.Enable('reconversion')
  return Fixture.new(previous, number, directory, popup_list(), snapshot)
enddef

def Cleanup(fixture: Fixture)
  try
    Caskk.Disable()
  finally
    for id in popup_list()
      if index(fixture.existing_popups, id) < 0
        popup_close(id)
      endif
    endfor
    execute 'noautocmd keepalt hide buffer ' .. fixture.previous
    execute 'silent! bwipeout! ' .. fixture.buffer
    delete(fixture.directory, 'rf')
    user_runtime.Get().Restore(fixture.snapshot)
    Caskk.Config({dictionaries: [], mappings: {}})
  endtry
enddef

def ConvertAndCommit()
  feedkeys("aKasc\<Esc>", 'xt')
  assert.equals(getline(1), '前蚊後')
enddef

suite.normal_mode_reconversion_selects_and_commits_a_different_candidate = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  ConvertAndCommit()
  cursor(1, 4)
  assert.equals(Caskk.Reconvert(), true)
  assert.equals(len(popup_list()), len(fixture.existing_popups) + 1)
  feedkeys("\<C-N>\<CR>", 'xt')
  assert.equals(getline(1), '前科後')
  assert.equals(maparg('<C-N>', 'n', false, true).rhs, '2j')
  undo
  assert.equals(getline(1), '前蚊後')
}

suite.canceling_reconversion_leaves_the_confirmed_text_untouched = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  ConvertAndCommit()
  const confirmed = getline(1)
  cursor(1, 4)
  assert.equals(Caskk.Reconvert(), true)
  feedkeys("\<Esc>", 'xt')
  assert.equals(getline(1), confirmed)
  assert.equals(popup_list(), fixture.existing_popups)
  assert.equals(maparg('<C-N>', 'n', false, true).rhs, '2j')
}

suite.cursor_movement_cancels_reconversion_and_restores_buffer_mappings = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  ConvertAndCommit()
  cursor(1, 4)
  assert.equals(Caskk.Reconvert(), true)
  assert.match(execute('autocmd caskk_reconversion'), 'CursorMoved')
  normal! l
  assert.equals(col('.'), 7)
  doautocmd <nomodeline> CursorMoved
  assert.equals(exists('#caskk_reconversion#CursorMoved'), 0)
  assert.equals(getline(1), '前蚊後')
  assert.equals(popup_list(), fixture.existing_popups)
  assert.equals(maparg('<C-N>', 'n', false, true).rhs, '2j')
}

suite.no_matching_recent_text_does_not_start_reconversion = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  setline(1, '未知')
  cursor(1, 1)
  assert.equals(Caskk.Reconvert(), false)
  assert.equals(getline(1), '未知')
}

suite.okuri_history_reconverts_using_its_exact_okuri_lookup = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys("aKaKuc\<Esc>", 'xt')
  assert.equals(getline(1), '前書く後')
  cursor(1, 4)
  assert.equals(Caskk.Reconvert(), true)
  feedkeys("\<CR>", 'xt')
  assert.equals(getline(1), '前書く後')
}
