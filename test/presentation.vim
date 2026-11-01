vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/buffer.vim' as buffer
import autoload 'caskk/presentation.vim' as presentation
import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state

final suite = themis#suite('preedit presentation integration')
const assert = themis#helper('assert')

def Scratch(): number
  const number = bufadd('')
  bufload(number)
  setbufvar(number, '&buftype', 'nofile')
  setbufvar(number, '&swapfile', false)
  return number
enddef

def Wipe(number: number)
  execute 'silent! bwipeout! ' .. number
enddef

def Apply(writer: buffer.Writer, view: presentation.Highlighter, results: list<session.Result>)
  for result in results
    view.Clear()
    writer.Apply(result)
    view.Render()
  endfor
enddef

suite.highlight_follows_reading_candidate_and_cancel_without_markers = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  const writer = buffer.Writer.new(number, 1, 4)
  const view = presentation.Highlighter.new(writer)
  const preferences = user_state.State.new()
  preferences.AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('漢字', []))
  preferences.AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('蚊', []))
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  Apply(writer, view, ime.Feed('K'))
  Apply(writer, view, ime.Feed('a'))
  assert.equals(prop_list(1, {bufnr: number})[0].col, 4)
  assert.equals(prop_list(1, {bufnr: number})[0].length, 3)
  Apply(writer, view, ime.StartConversion({}, preferences))
  assert.equals(getbufline(number, 1), ['前漢字後'])
  assert.equals(prop_list(1, {bufnr: number})[0].length, 6)
  view.Clear()
  writer.Apply(ime.SelectCandidate(1))
  view.Render()
  assert.equals(prop_list(1, {bufnr: number})[0].length, 3)
  view.Clear()
  writer.Apply(ime.CancelConversion())
  view.Render()
  view.Render()
  assert.equals(getbufline(number, 1), ['前か後'])
  const properties = prop_list(1, {bufnr: number})
  assert.equals(len(properties), 1)
  assert.equals(properties[0].col, 4)
  assert.equals(properties[0].length, 3)
  const definition = prop_type_get(properties[0].type, {bufnr: number})
  assert.equals(definition.highlight, 'CaskkPreedit')
}

suite.commit_removes_highlight_without_changing_text_or_undo_history = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  const writer = buffer.Writer.new(number, 1, 4)
  const view = presentation.Highlighter.new(writer)
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  Apply(writer, view, ime.Feed('K'))
  Apply(writer, view, ime.Feed('a'))
  const tick = getbufvar(number, 'changedtick')
  const sequence = get(undotree(number), 'seq_cur', 0)
  view.Render()
  assert.equals(getbufvar(number, 'changedtick'), tick)
  assert.equals(get(undotree(number), 'seq_cur', 0), sequence)
  Apply(writer, view, ime.Commit())
  assert.equals(getbufline(number, 1), ['前か後'])
  assert.equals(prop_list(1, {bufnr: number}), [])
}

suite.multiline_highlight_excludes_surrounding_text_and_is_cleared_on_cancel = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, ['前後', '次行'])
  const writer = buffer.Writer.new(number, 1, 4)
  const view = presentation.Highlighter.new(writer)
  const preferences = user_state.State.new()
  preferences.AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new("漢\n字", []))
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  Apply(writer, view, ime.Feed('K'))
  Apply(writer, view, ime.Feed('a'))
  Apply(writer, view, ime.StartConversion({}, preferences))
  const first = prop_list(1, {bufnr: number})
  const second = prop_list(2, {bufnr: number})
  assert.equals(first[0].col, 4)
  assert.equals(first[0].length, 4)
  assert.equals(second[0].col, 1)
  assert.equals(second[0].length, 3)
  assert.equals(prop_list(3, {bufnr: number}), [])
  view.Clear()
  writer.Apply(ime.CancelConversion())
  view.Render()
  assert.equals(getbufline(number, 1, '$'), ['前か後', '次行'])
  assert.equals(len(prop_list(1, {bufnr: number})), 1)
  assert.equals(prop_list(2, {bufnr: number}), [])
}

suite.empty_preedit_does_not_highlight_an_adjacent_character = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  const writer = buffer.Writer.new(number, 1, 4)
  const view = presentation.Highlighter.new(writer)
  const ime = session.Session.new(scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['x'], '')]))
  Apply(writer, view, ime.Feed('X'))
  assert.equals(writer.InPreedit(), true)
  assert.equals(prop_list(1, {bufnr: number}), [])
  assert.equals(getbufline(number, 1), ['前後'])
}

suite.clear_preserves_other_property_types_and_other_buffers = (): void => {
  const first = Scratch()
  defer Wipe(first)
  const second = Scratch()
  defer Wipe(second)
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'})
  const writer = buffer.Writer.new(first, 1, 1)
  const view = presentation.Highlighter.new(writer)
  const ime = session.Session.new(compiled)
  Apply(writer, view, ime.Feed('K'))
  Apply(writer, view, ime.Feed('a'))
  prop_type_add('other_plugin', {bufnr: first, highlight: 'Search'})
  prop_add(1, 1, {bufnr: first, type: 'other_plugin', length: 3})
  const other_writer = buffer.Writer.new(second, 1, 1)
  const other_view = presentation.Highlighter.new(other_writer)
  const other_ime = session.Session.new(compiled)
  Apply(other_writer, other_view, other_ime.Feed('K'))
  Apply(other_writer, other_view, other_ime.Feed('a'))
  view.Clear()
  view.Clear()
  assert.equals(len(prop_list(1, {bufnr: first})), 1)
  assert.equals(prop_list(1, {bufnr: first})[0].type, 'other_plugin')
  assert.equals(len(prop_list(1, {bufnr: second})), 1)
}
