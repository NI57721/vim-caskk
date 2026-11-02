vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/insert.vim' as insert
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('Insert-mode registration integration')
const assert = themis#helper('assert')
var editor: insert.Editor
var preferences: user_state.State
var entries: dict<dictionary.Entry> = {}
var requests: list<conversion.Candidates> = []
var errors: list<string> = []
var positions: list<list<number>> = []
var texts: list<string> = []
var initial_reading: string = ''
var highlight_counts: list<number> = []

def Handle(key: string)
  try
    if key ==# 'attach'
      const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
        scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい'),
      ])
      editor = insert.Editor.new(compiled, ';', entries, preferences, initial_reading)
    elseif key ==# 'request'
      requests->add(editor.GetRegistrationRequest())
      positions->add([line('.'), col('.')])
      texts->add(getline(1))
      highlight_counts->add(len(prop_list(1, {types: ['caskk_preedit']})))
    elseif key ==# 'register'
      editor.Register(dictionary.Candidate.new('課', ['登録注釈']))
    elseif key ==# 'okuri'
      editor.Register(dictionary.Candidate.new('行', ['移動']))
    elseif key ==# 'empty'
      editor.Register(dictionary.Candidate.new('', []))
    elseif key ==# 'cancel'
      editor.CancelRegistration()
    elseif key ==# 'moved'
      const position = getcurpos()
      cursor(1, 1)
      try
        editor.Register(dictionary.Candidate.new('不正', []))
      finally
        setpos('.', position)
      endtry
    elseif key ==# 's'
      editor.StartConversion()
    elseif key ==# 'n'
      editor.NextCandidate()
    elseif key ==# 'close'
      editor.Close()
    else
      editor.Feed(key)
    endif
  catch
    errors->add(v:exception)
  endtry
enddef

def Setup(): list<number>
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  preferences = user_state.State.new()
  entries = {}
  requests = []
  errors = []
  positions = []
  texts = []
  initial_reading = ''
  highlight_counts = []
  for key in ['k', 'a', 'K', 'Z', 'X', 's', 'n']
    execute 'inoremap <buffer> ' .. key .. " <ScriptCmd>Handle('" .. key .. "')<CR>"
  endfor
  inoremap <buffer> <F2> <ScriptCmd>Handle('attach')<CR>
  inoremap <buffer> <F3> <ScriptCmd>Handle('register')<CR>
  inoremap <buffer> <F4> <ScriptCmd>Handle('okuri')<CR>
  inoremap <buffer> <F5> <ScriptCmd>Handle('cancel')<CR>
  inoremap <buffer> <F6> <ScriptCmd>Handle('request')<CR>
  inoremap <buffer> <F7> <ScriptCmd>Handle('empty')<CR>
  inoremap <buffer> <F8> <ScriptCmd>Handle('moved')<CR>
  inoremap <buffer> <Esc> <ScriptCmd>Handle('close')<CR><Esc>
  return [previous, number]
enddef

def Cleanup(context: list<number>)
  editor = null_object
  execute 'noautocmd keepalt hide buffer ' .. context[0]
  execute 'silent! bwipeout! ' .. context[1]
enddef

suite.initial_reading_is_rendered_at_the_cursor_and_converts_with_normal_undo = (): void => {
  const context = Setup()
  defer Cleanup(context)
  initial_reading = 'か'
  entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  feedkeys("a\<F2>\<F6>s\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(texts, ['前か後'])
  assert.equals(highlight_counts, [1])
  assert.equals(positions, [[1, 7]])
  assert.equals(requests[0] is null_object, true)
  assert.equals(getline(1), '前蚊後')
  normal! u
  assert.equals(getline(1), '前か後')
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  normal! u
  assert.equals(getline(1), '前後')
}

suite.initial_reading_and_following_plain_input_share_one_preedit_undo_unit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  initial_reading = 'か'
  feedkeys("a\<F2>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前かか後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.initial_asterisk_remains_a_literal_buffer_character = (): void => {
  const context = Setup()
  defer Cleanup(context)
  initial_reading = 'か*'
  feedkeys("a\<F2>\<F6>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(texts, ['前か*後'])
  assert.equals(positions, [[1, 8]])
  assert.equals(getline(1), '前か*後')
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
}

suite.register_replaces_reading_and_keeps_cursor_learning_and_undo_boundaries = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>Kas\<F6>\<F3>\<F6>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(requests[0].query.reading, 'か')
  assert.equals(requests[0].okuri, '')
  assert.equals(requests[0].candidates, [])
  assert.equals(requests[1] is null_object, true)
  assert.equals(texts, ['前か後', '前課後'])
  assert.equals(positions, [[1, 7], [1, 7]])
  assert.equals(getline(1), '前課か後')
  const snapshot = preferences.GetSnapshot()
  const identity = json_encode(['か', ''])
  assert.equals(snapshot.entries[identity][0].text, '課')
  assert.equals(snapshot.entries[identity][0].annotations, ['登録注釈'])
  assert.equals(snapshot.mru[identity], ['課'])
  for expected in ['前課後', '前か後', '前後']
    normal! u
    assert.equals(getline(1), expected)
    assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  endfor
}

suite.okuri_registration_uses_first_exact_character_and_commits_full_suffix = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>ZX\<F6>\<F4>\<F6>ZX\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(requests[0].query.reading, 'い')
  assert.equals(requests[0].query.exact_okuri, 'く')
  assert.equals(requests[0].query.lookup_key, 'いk')
  assert.equals(requests[0].okuri, 'くらい')
  assert.equals(requests[1] is null_object, true)
  assert.equals(getline(1), '前行くらい行くらい後')
  const stored = preferences.GetSnapshot().entries[json_encode(['い', 'く'])]
  assert.equals(len(stored), 1)
  assert.equals(stored[0].text, '行')
  assert.equals(stored[0].annotations, ['移動'])
}

suite.cancelling_registration_keeps_reading_editable_without_learning = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const before = codec.Encode(preferences.GetSnapshot())
  feedkeys("a\<F2>Kas\<F6>\<F5>\<F6>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(requests[0] isnot null_object, true)
  assert.equals(requests[1] is null_object, true)
  assert.equals(texts, ['前か後', '前か後'])
  assert.equals(getline(1), '前かか後')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.cancelling_exhausted_okuri_registration_preserves_full_reading_for_following_input = (): void => {
  const context = Setup()
  defer Cleanup(context)
  entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const before = codec.Encode(preferences.GetSnapshot())
  feedkeys("a\<F2>ZXn\<F6>\<F5>\<F6>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(requests[0].query.exact_okuri, 'く')
  assert.equals(requests[0].okuri, 'くらい')
  assert.equals(len(requests[0].candidates), 1)
  assert.equals(requests[1] is null_object, true)
  assert.equals(getline(1), '前いくらいか後')
  assert.equals(codec.Encode(preferences.GetSnapshot()), before)
}

suite.empty_registration_keeps_request_and_allows_retry = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>Kas\<F7>\<F6>\<F3>\<Esc>", 'xt')
  assert.equals(errors, ['caskk: registered candidate text must not be empty'])
  assert.equals(requests[0].query.reading, 'か')
  assert.equals(texts, ['前か後'])
  assert.equals(getline(1), '前課後')
  assert.equals(len(preferences.GetSnapshot().entries[json_encode(['か', ''])]), 1)
}

suite.no_request_is_exposed_during_direct_preedit_or_candidate_selection = (): void => {
  const context = Setup()
  defer Cleanup(context)
  entries = merger.Merge([[parser.ParseLine('か /蚊/')]])
  feedkeys("a\<F2>\<F6>Ka\<F6>s\<F6>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(len(requests), 3)
  for request in requests
    assert.equals(request is null_object, true)
  endfor
  assert.equals(editor.GetRegistrationRequest() is null_object, true)
  assert.equals(getline(1), '前蚊後')
}

suite.moved_cursor_is_rejected_before_registration_changes_user_state = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>Kas\<F8>\<F6>\<F3>\<Esc>", 'xt')
  assert.equals(errors, ['caskk: cursor moved outside the tracked input position'])
  assert.equals(requests[0].query.reading, 'か')
  assert.equals(getline(1), '前課後')
  const stored = preferences.GetSnapshot().entries[json_encode(['か', ''])]
  assert.equals(len(stored), 1)
  assert.equals(stored[0].text, '課')
}
