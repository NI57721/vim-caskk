vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/scheme.vim' as scheme

final suite = themis#suite('shared public user state')
const assert = themis#helper('assert')

def Setup(reading: string): list<number>
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  Caskk.RegisterInputScheme('shared-state', {k: 'k'}, {u: 'u', i: 'i'}, [
    scheme.SpecialDefinition.new(['x'], reading),
  ])
  return [previous, number]
enddef

def Cleanup(context: list<number>)
  try
    Caskk.Disable()
    Caskk.Config({})
  finally
    execute 'noautocmd keepalt hide buffer ' .. context[0]
    execute 'silent! bwipeout! ' .. context[1]
  endtry
enddef

suite.learned_candidate_survives_disable_and_reenable = (): void => {
  const context = Setup('さいきどう')
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['さいきどう /再起動/再始動/'], path)
  const original = readblob(path)
  Caskk.Config({dictionaries: [path], mappings: {s: 'StartConversion', n: 'NextCandidate'}})
  Caskk.Enable('shared-state')
  feedkeys("aXsn\<Esc>", 'xt')
  assert.equals(getline(1), '前再始動後')
  Caskk.Disable()
  Caskk.Enable('shared-state')
  feedkeys("aXs\<Esc>", 'xt')
  assert.equals(getline(1), '前再始動再始動後')
  assert.equals(readblob(path), original)
}

suite.learning_in_another_buffer_updates_an_already_enabled_buffer = (): void => {
  const first = Setup('べつばっふぁ')
  defer Cleanup(first)
  const path = tempname()
  defer delete(path)
  writefile(['べつばっふぁ /第一/第二/'], path)
  Caskk.Config({dictionaries: [path], mappings: {s: 'StartConversion', n: 'NextCandidate'}})
  Caskk.Enable('shared-state')
  const second = Setup('べつばっふぁ')
  try
    Caskk.Enable('shared-state')
    feedkeys("aXsn\<Esc>", 'xt')
    assert.equals(getline(1), '前第二後')
    Caskk.Disable()
    execute 'noautocmd keepalt hide buffer ' .. first[1]
    feedkeys("aXs\<Esc>", 'xt')
    assert.equals(getline(1), '前第二後')
  finally
    Cleanup(second)
  endtry
}

suite.reconfiguring_dictionaries_and_highlight_does_not_clear_learning = (): void => {
  const context = Setup('せってい')
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['せってい /設定/設定位/'], path)
  Caskk.Config({dictionaries: [path], mappings: {s: 'StartConversion', n: 'NextCandidate'}})
  Caskk.Enable('shared-state')
  feedkeys("aXsn\<Esc>", 'xt')
  assert.equals(getline(1), '前設定位後')
  Caskk.Disable()
  Caskk.Config({})
  Caskk.Config({dictionaries: [path], mappings: {s: 'StartConversion'},
    highlight: {preedit: {cterm: 'bold'}}})
  Caskk.Enable('shared-state')
  feedkeys("aXs\<Esc>", 'xt')
  assert.equals(getline(1), '前設定位設定位後')
}

suite.shared_learning_keeps_different_exact_okuri_histories_separate = (): void => {
  const context = Setup('き')
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['きk /聞/聴/'], path)
  Caskk.Config({dictionaries: [path], mappings: {n: 'NextCandidate'}})
  Caskk.Enable('shared-state')
  feedkeys("aXKun\<Esc>", 'xt')
  assert.equals(getline(1), '前聴く後')
  Caskk.Disable()
  Caskk.Enable('shared-state')
  feedkeys("aXKi\<Esc>", 'xt')
  assert.equals(getline(1), '前聴く聞き後')
  Caskk.Disable()
  Caskk.Enable('shared-state')
  feedkeys("aXKu\<Esc>", 'xt')
  assert.equals(getline(1), '前聴く聞き聴く後')
}
