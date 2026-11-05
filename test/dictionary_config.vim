vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime

final suite = themis#suite('public system dictionary configuration')
const assert = themis#helper('assert')
var previous_state: user_state.Snapshot

def Setup(): list<number>
  previous_state = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  Caskk.Config({})
  Caskk.RegisterInputScheme({name: 'dictionary-config', consonants: {k: 'k'},
    combinations: {a: 'a'}, specials: {x: 'かな'}})
  return [previous, number]
enddef

def Cleanup(context: list<number>)
  try
    Caskk.Disable()
    Caskk.Config({})
  finally
    user_runtime.Get().Restore(previous_state)
    execute 'noautocmd keepalt hide buffer ' .. context[0]
    execute 'silent! bwipeout! ' .. context[1]
  endtry
enddef

suite.public_conversion_uses_merged_source_order_without_duplicate_candidates = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const first = tempname()
  const second = tempname()
  defer delete(first)
  defer delete(second)
  writefile(['か /蚊/科/'], first)
  writefile(['か /蚊/課/'], second)
  const original = [readblob(first), readblob(second)]
  Caskk.Config({dictionaries: [first, second], mappings: {s: 'Convert', n: 'NextCandidate'}})
  Caskk.Enable('dictionary-config')
  for [steps, expected] in [[0, '蚊'], [1, '科'], [2, '課']]
    setline(1, '前後')
    cursor(1, 1)
    feedkeys('aKas' .. repeat('n', steps) .. "\<Esc>", 'xt')
    assert.equals(getline(1), '前' .. expected .. '後')
  endfor
  assert.equals([readblob(first), readblob(second)], original)
}

suite.explicit_source_encoding_is_used_by_public_conversion = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  # EUC-JP bytes for 'かな /仮名;注釈/' and LF.
  writefile(0zA4ABA4CA202FB2BECCBE3BC3EDBCE12F0A, path)
  Caskk.Config({dictionaries: [{path: path, encoding: 'euc-jp'}], mappings: {s: 'Convert'}})
  Caskk.Enable('dictionary-config')
  feedkeys("aXs\<Esc>", 'xt')
  assert.equals(getline(1), '前仮名後')
}

suite.configuration_loads_eagerly_and_does_not_retain_source_containers = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['か /蚊/'], path)
  final source = {path: path}
  final sources = [source]
  Caskk.Config({dictionaries: sources, mappings: {s: 'Convert'}})
  source.path = path .. '-missing'
  sources->remove(0)
  delete(path)
  Caskk.Enable('dictionary-config')
  feedkeys("aKas\<Esc>", 'xt')
  assert.equals(getline(1), '前蚊後')
}

suite.updated_dictionary_is_applied_after_disabling_and_reenabling = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['か /蚊/'], path)
  Caskk.Config({dictionaries: [path], mappings: {s: 'Convert'}})
  Caskk.Enable('dictionary-config')
  feedkeys("aKas\<Esc>", 'xt')
  assert.equals(getline(1), '前蚊後')
  writefile(['か /科/'], path)
  Caskk.Config({dictionaries: [path], mappings: {s: 'Convert'}})
  assert.equals(Caskk.IsEnabled(), false)
  Caskk.Enable('dictionary-config')
  feedkeys("aKas\<Esc>", 'xt')
  assert.equals(getline(1), '前蚊科後')
}

suite.invalid_source_shapes_and_fields_are_rejected_without_changing_settings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  Caskk.Config({sticky_key: ';', highlight: {preedit: {cterm: 'bold'}}})
  const before = hlget('CaskkPreedit')
  for [sources, expected] in [
    [1, 'dictionaries must be a list'], [{}, 'dictionaries must be a list'],
    ['', 'dictionaries must be a list'],
    [[1], 'dictionary source must be a path string or dictionary'],
    [[{}], 'dictionary source path must be a string'],
    [[''], 'dictionary source path must not be empty'],
    [[{path: ''}], 'dictionary source path must not be empty'],
    [[{path: 1}], 'dictionary source path must be a string'],
    [[{path: 'unused', encoding: 1}], 'dictionary source encoding must be a string'],
    [[{path: 'unused', encoding: ''}], 'dictionary source encoding must not be empty'],
    [[{path: 'unused', typo: 'utf-8'}], 'unknown dictionary source field: typo'],
  ]
    var caught = ''
    try
      Caskk.Config({dictionaries: sources})
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: invalid configuration: ' .. expected)
    assert.equals(hlget('CaskkPreedit'), before)
  endfor
  Caskk.Enable('dictionary-config')
  feedkeys("a;ka\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
}

suite.read_and_decode_failures_keep_previous_dictionary_and_input_settings = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const previous = tempname()
  const invalid_bytes = tempname()
  const missing = tempname()
  defer delete(previous)
  defer delete(invalid_bytes)
  writefile(['か /蚊/'], previous)
  writefile(0zFF, invalid_bytes)
  Caskk.Config({dictionaries: [previous], sticky_key: ';', mappings: {s: 'Convert'},
    highlight: {preedit: {cterm: 'bold'}}})
  const before = hlget('CaskkPreedit')
  for path in [missing, invalid_bytes]
    var caught = ''
    try
      Caskk.Config({dictionaries: [previous, path], highlight: {preedit: {cterm: 'reverse'}}})
    catch
      caught = v:exception
    endtry
    assert.equals(stridx(caught, 'caskk: invalid configuration:'), 0)
    assert.equals(stridx(caught, path) >= 0, true)
    assert.equals(hlget('CaskkPreedit'), before)
  endfor
  Caskk.Enable('dictionary-config')
  feedkeys("a;kas\<Esc>", 'xt')
  assert.equals(getline(1), '前蚊後')
}

suite.configuration_skips_malformed_dictionary_lines_and_loads_later_entries = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['かな /未完', 'かな /仮名/'], path)
  Caskk.Config({dictionaries: [path], mappings: {s: 'Convert'}})
  Caskk.Enable('dictionary-config')
  feedkeys("aXs\<Esc>", 'xt')
  assert.equals(getline(1), '前仮名後')
}

suite.highlight_failure_does_not_publish_a_newly_loaded_dictionary = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['か /蚊/'], path)
  Caskk.Config({dictionaries: [path], mappings: {s: 'Convert'}})
  const before = hlget('CaskkPreedit')
  writefile(['か /科/'], path)
  var caught = ''
  try
    Caskk.Config({dictionaries: [path], mappings: {s: 'Convert'},
      highlight: {preedit: {ctermfg: 'caskk-invalid-color'}}})
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: invalid configuration:'), 0)
  assert.equals(hlget('CaskkPreedit'), before)
  Caskk.Enable('dictionary-config')
  feedkeys("aKas\<Esc>", 'xt')
  assert.equals(getline(1), '前蚊後')
}

suite.omitting_dictionaries_removes_previously_loaded_candidates = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const path = tempname()
  defer delete(path)
  writefile(['か /蚊/'], path)
  Caskk.Config({dictionaries: [path], mappings: {s: 'Convert'}})
  Caskk.Config({mappings: {s: 'Convert'}})
  Caskk.Enable('dictionary-config')
  feedkeys("aKas\<Esc>", 'xt')
  assert.equals(getline(1), '前か後')
}
