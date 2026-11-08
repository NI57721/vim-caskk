vim9script

import 'caskk/input.vim' as input
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/insert.vim' as insert
import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('Insert-mode controller')
const assert = themis#helper('assert')
var editor: insert.Editor
var compiled: scheme.CompiledScheme
var preferences: user_state.State
var errors: list<string> = []
var positions: list<list<number>> = []
var marker_counts: list<number> = []
var unhandled: list<input.Event> = []
var deletions: list<bool> = []
var preedit_states: list<bool> = []
var readings: list<string> = []
var okuris: list<string> = []
var okuri_started: list<bool> = []

def Handle(key: string)
  try
    if key ==# 'attach'
      const entries = merger.Merge([[parser.ParseLine('か /蚊/科/'), parser.ParseLine('いk /行/')]])
      editor = insert.Editor.new(compiled, ';', entries, preferences)
      return
    endif
    if key ==# 'P'
      positions->add([line('.'), col('.')])
      preedit_states->add(editor.GetSnapshot().in_preedit)
      readings->add(editor.GetSnapshot().reading)
      okuris->add(editor.GetSnapshot().okuri)
      okuri_started->add(editor.GetSnapshot().okuri_started)
      var markers = 0
      for property in prop_list(1, {end_lnum: -1})
        if get(property, 'text', '') ==# '*'
          markers += 1
        endif
      endfor
      marker_counts->add(markers)
      return
    endif
    if key ==# 'delete-preedit'
      deletions->add(editor.Backspace())
      return
    endif
    if key ==# '<BS>'
      deletions->add(editor.BackspacePending())
      return
    endif
    var results: list<session.Result> = []
    if key ==# 'S'
      results = editor.StartConversion()
    elseif key ==# 'N'
      results = [editor.NextCandidate()]
    elseif key ==# 'B'
      results = [editor.PreviousCandidate()]
    elseif key ==# 'C'
      results = editor.Commit()
    elseif key ==# 'close'
      results = editor.Close()
    else
      results = editor.Feed(key)
    endif
    for result in results
      unhandled->extend(result.unhandled)
    endfor
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
  compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [
    scheme.SpecialDefinition.new(['d'], '。'),
    scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい'),
  ])
  preferences = user_state.State.new()
  errors = []
  positions = []
  marker_counts = []
  unhandled = []
  deletions = []
  preedit_states = []
  readings = []
  okuris = []
  okuri_started = []
  for key in ['k', 'a', 'K', ';', 'Z', 'X', 'd', 'S', 'N', 'B', 'C', 'P', '?']
    execute 'inoremap <buffer> ' .. key .. " <ScriptCmd>Handle('" .. key .. "')<CR>"
  endfor
  inoremap <buffer> <F2> <ScriptCmd>Handle('attach')<CR>
  inoremap <buffer> <BS> <ScriptCmd>Handle('<lt>BS>')<CR>
  inoremap <buffer> <F11> <ScriptCmd>Handle('<lt>F11>')<CR>
  inoremap <buffer> <Esc> <ScriptCmd>Handle('close')<CR><Esc>
  return [previous, number]
enddef

def Cleanup(context: list<number>)
  editor = null_object
  execute 'noautocmd keepalt hide buffer ' .. context[0]
  execute 'silent! bwipeout! ' .. context[1]
enddef

suite.backspace_preserves_modifier_and_cursor_until_replacement_input = (): void => {
  for keys in ["K\<BS>", ";k\<BS>"]
    const context = Setup()
    try
      feedkeys("a\<F2>" .. keys .. "PkaP\<Esc>", 'xt')
      assert.equals(errors, [])
      assert.equals(deletions, [true])
      assert.equals(positions, [[1, 4], [1, 7]])
      assert.equals(preedit_states, [false, true])
      assert.equals(getline(1), '前か後')
      assert.equals(editor.GetSnapshot().in_preedit, false)
      normal! u
      assert.equals(getline(1), '前後')
    finally
      Cleanup(context)
    endtry
  endfor
}

suite.standard_romaji_vowels_continue_after_consonant_syllables = (): void => {
  const context = Setup()
  try
    compiled = scheme.Compile({h: 'h', g: 'g'}, {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'})
    editor = null_object
    inoremap <buffer> h <ScriptCmd>Handle('h')<CR>
    inoremap <buffer> o <ScriptCmd>Handle('o')<CR>
    inoremap <buffer> g <ScriptCmd>Handle('g')<CR>
    inoremap <buffer> e <ScriptCmd>Handle('e')<CR>
    inoremap <buffer> i <ScriptCmd>Handle('i')<CR>
    inoremap <buffer> u <ScriptCmd>Handle('u')<CR>
    inoremap <buffer> a <ScriptCmd>Handle('a')<CR>
    feedkeys("a\<F2>hogeaiueo\<Esc>", 'xt')
    assert.equals(errors, [])
    assert.equals(getline(1), '前ほげあいうえお後')
  finally
    Cleanup(context)
  endtry
}

suite.repeated_m_keys_apply_modified_okuri_rules_in_insert_mode = (): void => {
  for [keys, expected_text, expected_reading, expected_okuri, expected_boundary] in [
    ['mm', '前まく後', '', '', false],
    [';mm', '前まく後', 'まく', '', false],
    [';m;m', '前まく後', 'ま', 'く', true],
  ]
    const context = Setup()
    try
      compiled = scheme.Compile({m: 'm'}, {m: 'a*ku'})
      editor = null_object
      inoremap <buffer> m <ScriptCmd>Handle('m')<CR>
      feedkeys("a\<F2>" .. keys .. "P\<Esc>", 'xt')
      assert.equals(errors, [])
      assert.equals(getline(1), expected_text)
      assert.equals(readings, [expected_reading])
      assert.equals(okuris, [expected_okuri])
      assert.equals(okuri_started, [expected_boundary])
      assert.equals(marker_counts, [expected_boundary ? 1 : 0])
    finally
      Cleanup(context)
    endtry
  endfor
}

suite.backspace_reports_empty_pending_input_without_deleting_buffer_text = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>K\<BS>\<BS>\<BS>Pka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(deletions, [true, true, false])
  assert.equals(positions, [[1, 4]])
  assert.equals(preedit_states, [false])
  assert.equals(getline(1), '前か後')
}

suite.direct_input_updates_the_real_insert_cursor_between_multibyte_characters = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>kaPkaP\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前かか後')
  assert.equals(positions, [[1, 7], [1, 10]])
  assert.equals(editor.IsClosed(), true)
  normal! u
  assert.equals(getline(1), '前後')
}

suite.candidate_commit_keeps_cursor_and_undo_boundaries_for_following_input = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>KaSNCPd\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前科。後')
  assert.equals(positions, [[1, 7]])
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  normal! u
  assert.equals(getline(1), '前科後')
  normal! u
  assert.equals(getline(1), '前か後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.virtual_okuri_marker_does_not_shift_the_physical_insert_position = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>ZXBPka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(positions, [[1, 16]])
  assert.equals(marker_counts, [1])
  assert.equals(getline(1), '前いくらいか後')
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
}

suite.closing_commits_reading_clears_presentation_and_is_idempotent = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>Ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前か後')
  assert.equals(editor.IsClosed(), true)
  assert.equals(editor.GetSnapshot().in_preedit, false)
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  assert.equals(editor.Close(), [])
  var caught = ''
  try
    editor.Feed('k')
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: Insert-mode editor is closed')
}

suite.cursor_movement_is_detected_before_consuming_new_input = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>ka\<Left>k\<Esc>", 'xt')
  assert.equals(errors, ['caskk: cursor moved outside the tracked input position'])
  assert.equals(getline(1), '前か後')
  assert.equals(editor.Pending(), [])
}

suite.unhandled_events_are_returned_to_the_key_dispatch_layer = (): void => {
  const context = Setup()
  defer Cleanup(context)
  feedkeys("a\<F2>\<F11>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前後')
  assert.equals(len(unhandled), 1)
  assert.equals(unhandled[0].key, '<F11>')
}

suite.multiline_candidates_position_the_cursor_before_the_preserved_suffix = (): void => {
  const context = Setup()
  defer Cleanup(context)
  preferences.AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new("漢\n字", []))
  preferences.Pin(lookup.CreateQuery('か', ''), "漢\n字")
  feedkeys("a\<F2>KaSCPd\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(positions, [[2, 4]])
  assert.equals(getline(1, '$'), ['前漢', '字。後'])
  normal! u
  assert.equals(getline(1, '$'), ['前漢', '字後'])
  normal! u
  assert.equals(getline(1, '$'), ['前か後'])
}

suite.attachment_outside_insert_mode_is_rejected = (): void => {
  const context = Setup()
  defer Cleanup(context)
  var caught = ''
  try
    insert.Editor.new(compiled)
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: editor must be started in Insert mode')
  assert.equals(getline(1), '前後')
}

suite.insert_cursor_can_advance_past_the_last_byte_of_the_line = (): void => {
  const context = Setup()
  defer Cleanup(context)
  setline(1, '')
  cursor(1, 1)
  feedkeys("i\<F2>kaPkaP\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), 'かか')
  assert.equals(positions, [[1, 4], [1, 7]])
}

suite.insertleave_closes_preedit_without_moving_the_normal_cursor_to_the_suffix = (): void => {
  const context = Setup()
  defer Cleanup(context)
  iunmap <buffer> <Esc>
  augroup caskk_insert_test
    autocmd! * <buffer>
    autocmd InsertLeave <buffer> Handle('close')
  augroup END
  feedkeys("a\<F2>Ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(editor.IsClosed(), true)
  assert.equals(getline(1), '前か後')
  assert.equals(col('.'), 4)
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
}


suite.empty_preedit_commit_and_leave_close_without_extra_undo = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <F4> <ScriptCmd>Handle('delete-preedit')<CR>
  feedkeys("a\<F2>kaCKa\<F4>PCd\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(preedit_states, [true])
  assert.equals(readings, [''])
  assert.equals(getline(1), '前か。後')
  assert.equals(editor.IsClosed(), true)
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
  normal! u
  assert.equals(getline(1), '前か後')
  normal! u
  assert.equals(getline(1), '前後')
}


suite.insertleave_closes_an_empty_preedit_range = (): void => {
  const context = Setup()
  defer Cleanup(context)
  inoremap <buffer> <F4> <ScriptCmd>Handle('delete-preedit')<CR>
  feedkeys("a\<F2>Ka\<F4>P\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(preedit_states, [true])
  assert.equals(editor.IsClosed(), true)
  assert.equals(getline(1), '前後')
  assert.equals(prop_list(1, {types: ['caskk_preedit']}), [])
}
