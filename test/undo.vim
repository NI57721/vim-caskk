vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/buffer.vim' as buffer
import autoload 'caskk/undo.vim' as undo
import autoload 'caskk/presentation.vim' as presentation
import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('semantic undo integration')
const assert = themis#helper('assert')
var ime: session.Session
var manager: undo.Manager
var preferences: user_state.State
var view: presentation.Highlighter

def Handle(key: string)
  var results: list<session.Result> = []
  if key ==# 'S'
    results = ime.StartConversion(merger.Merge([[parser.ParseLine('か /蚊/科/')]]), preferences)
  elseif key ==# 'N'
    results = [ime.NextCandidate()]
  elseif key ==# 'B'
    results = [ime.PreviousCandidate()]
  elseif key ==# 'C'
    results = ime.Commit()
  elseif key ==# 'R'
    results = [ime.Register(dictionary.Candidate.new('課', []))]
  else
    results = ime.Feed(key)
  endif
  for result in results
    view.Clear()
    manager.Apply(result)
    view.Render(result)
  endfor
enddef

def Setup(revert_to_reading: bool = true): list<number>
  const previous = bufnr('%')
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  setlocal buftype=nofile noswapfile undolevels=37
  preferences = user_state.State.new()
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['d'], 'ました。'),
    scheme.SpecialDefinition.new(['g', 'h'], 'い*きます'),
    scheme.SpecialDefinition.new(['v', 'w'], 'い*く'),
    scheme.SpecialDefinition.new(['t'], 'というからには'),
  ])
  ime = session.Session.new(compiled, '', merger.Merge([[parser.ParseLine('いk /行/')]]), preferences)
  const writer = buffer.Writer.new(number, 1, 1)
  manager = undo.Manager.new(writer, revert_to_reading)
  view = presentation.Highlighter.new(writer)
  for key in ['k', 'a', 'K', 'd', 'S', 'N', 'B', 'C', 'R', 'G', 'H', 'V', 'W', 't']
    execute 'inoremap <buffer> ' .. key .. " <ScriptCmd>Handle('" .. key .. "')<CR>"
  endfor
  inoremap <buffer> <Esc> <ScriptCmd>manager.Close()<CR><Esc>
  return [previous, number]
enddef

def Cleanup(context: list<number>)
  execute 'noautocmd keepalt hide buffer ' .. context[0]
  execute 'silent! bwipeout! ' .. context[1]
enddef

suite.candidate_updates_and_direct_runs_undo_at_semantic_boundaries = (): void => {
  const context = Setup()
  defer Cleanup(context)
  const global_levels = &g:undolevels
  feedkeys("idKaSNCdd\<Esc>", 'xt')
  assert.equals(getline(1), 'ました。科ました。ました。')
  assert.equals(&g:undolevels, global_levels)
  assert.equals(&l:undolevels, 37)
  normal! u
  assert.equals(getline(1), 'ました。科')
  normal! u
  assert.equals(getline(1), 'ました。か')
  normal! u
  assert.equals(getline(1), 'ました。')
  normal! u
  assert.equals(getline(1), '')
  execute "normal! \<C-r>"
  assert.equals(getline(1), 'ました。')
  execute "normal! \<C-r>"
  assert.equals(getline(1), 'ました。か')
  execute "normal! \<C-r>"
  assert.equals(getline(1), 'ました。科')
}

suite.cancelled_conversion_and_reading_commit_form_one_undo_unit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("iKaSNBBC\<Esc>", 'xt')
  assert.equals(getline(1), 'か')
  normal! u
  assert.equals(getline(1), '')
  execute "normal! \<C-r>"
  assert.equals(getline(1), 'か')
}

suite.disabling_reading_restore_undoes_conversion_and_reading_together = (): void => {
  const context = Setup(false)
  defer Cleanup(context)
  feedkeys("iKaSC\<Esc>", 'xt')
  assert.equals(getline(1), '蚊')
  normal! u
  assert.equals(getline(1), '')
  execute "normal! \<C-r>"
  assert.equals(getline(1), '蚊')
}

suite.multiline_conversion_undo_restores_reading_before_removing_it = (): void => {
  const context = Setup()
  defer Cleanup(context)
  preferences.AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new("漢\n字", []))
  preferences.Pin(lookup.CreateQuery('か', ''), "漢\n字")
  feedkeys("iKaSC\<Esc>", 'xt')
  assert.equals(getline(1, '$'), ['漢', '字'])
  normal! u
  assert.equals(getline(1, '$'), ['か'])
  normal! u
  assert.equals(getline(1, '$'), [''])
  execute "normal! \<C-r>"
  assert.equals(getline(1, '$'), ['か'])
  execute "normal! \<C-r>"
  assert.equals(getline(1, '$'), ['漢', '字'])
}

suite.consecutive_undo_restores_plain_readings_without_reopening_conversion = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("iGHCtVWC\<Esc>", 'xt')
  assert.equals(getline(1), '行きますというからには行く')
  for expected in ['行きますというからにはいく', '行きますというからには', '行きます', 'いきます', '']
    normal! u
    assert.equals(getline(1), expected)
    assert.equals(ime.InCandidate(), false)
    assert.equals(ime.GetSnapshot().in_preedit, false)
    assert.equals(prop_list(1, {types: ['caskk_preedit'], end_lnum: -1}), [])
  endfor
  for expected in ['いきます', '行きます', '行きますというからには', '行きますというからにはいく', '行きますというからには行く']
    execute "normal! \<C-r>"
    assert.equals(getline(1), expected)
    assert.equals(ime.InCandidate(), false)
    assert.equals(ime.GetSnapshot().in_preedit, false)
    assert.equals(prop_list(1, {types: ['caskk_preedit'], end_lnum: -1}), [])
  endfor
}

suite.registration_commit_also_leaves_a_plain_reading_checkpoint = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("iKaSNNR\<Esc>", 'xt')
  assert.equals(getline(1), '課')
  normal! u
  assert.equals(getline(1), 'か')
  normal! u
  assert.equals(getline(1), '')
  execute "normal! \<C-r>"
  assert.equals(getline(1), 'か')
  execute "normal! \<C-r>"
  assert.equals(getline(1), '課')
}

suite.identical_reading_and_candidate_do_not_add_a_redundant_undo_step = (): void => {
  const context = Setup()
  defer Cleanup(context)
  preferences.AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('か', []))
  preferences.Pin(lookup.CreateQuery('か', ''), 'か')
  feedkeys("iKaSC\<Esc>", 'xt')
  assert.equals(getline(1), 'か')
  normal! u
  assert.equals(getline(1), '')
  execute "normal! \<C-r>"
  assert.equals(getline(1), 'か')
}

suite.okuri_marker_is_not_restored_when_undoing_a_plain_reading_commit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("iGHBC\<Esc>", 'xt')
  assert.equals(getline(1), 'いきます')
  assert.equals(prop_list(1, {types: ['caskk_preedit'], end_lnum: -1}), [])
  normal! u
  assert.equals(getline(1), '')
  execute "normal! \<C-r>"
  assert.equals(getline(1), 'いきます')
  assert.equals(prop_list(1, {types: ['caskk_preedit'], end_lnum: -1}), [])
  assert.equals(ime.GetSnapshot().in_preedit, false)
}

suite.external_changes_are_not_joined_into_the_ime_undo_unit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("id\<Esc>", 'xt')
  setline(1, '外部編集')
  const sequence = get(undotree(), 'seq_cur', 0)
  var caught = ''
  try
    Handle('d')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: buffer changed outside the managed undo unit')
  assert.equals(getline(1), '外部編集')
  assert.equals(get(undotree(), 'seq_cur', 0), sequence)
}

suite.a_different_current_buffer_is_rejected_before_editing = (): void => {
  const context = Setup()
  defer Cleanup(context)
  execute 'noautocmd keepalt hide buffer ' .. context[0]
  const before = getline(1, '$')
  var caught = ''
  try
    Handle('d')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: undo target must be the current buffer')
  assert.equals(getline(1, '$'), before)
  assert.equals(getbufline(context[1], 1, '$'), [''])
}

suite.user_undo_is_detected_before_attempting_to_join_a_new_edit = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("id\<Esc>", 'xt')
  normal! u
  assert.equals(getline(1), '')
  const sequence = get(undotree(), 'seq_cur', 0)
  var caught = ''
  try
    Handle('d')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: buffer changed outside the managed undo unit')
  assert.equals(getline(1), '')
  assert.equals(get(undotree(), 'seq_cur', 0), sequence)
}
