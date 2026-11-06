vim9script

import autoload 'caskk/registration/editor.vim' as registration_editor
import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/user_state.vim' as user_state

const suite = themis#suite('registration editing model')
const assert = themis#helper('assert')

suite.unicode_insertion_motion_and_deletion_use_character_positions = (): void => {
  const editor = registration_editor.Editor.new(session.Session.new(scheme.Compile({}, {})))
  editor.InsertLiteral('あいう')
  editor.Move(-1)
  editor.InsertLiteral('漢字')
  assert.equals(editor.GetText(), 'あい漢字う')
  assert.equals(editor.GetCursor(), 4)
  editor.Delete(true)
  editor.Delete(false)
  assert.equals(editor.GetText(), 'あい漢')
  editor.Move(-99)
  editor.Delete(true)
  editor.Move(99)
  editor.Delete(false)
  assert.equals(editor.GetText(), 'あい漢')
}

suite.literal_paste_commits_pending_input_before_inserting_without_interpretation = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  const editor = registration_editor.Editor.new(ime)
  editor.Append(ime.Feed('k'))
  editor.Paste('Ka<CR>漢字')
  assert.equals(editor.GetText(), 'kKa<CR>漢字')
  assert.equals(ime.Pending(), [])
  assert.equals(ime.GetSnapshot().in_preedit, false)
}

suite.candidate_is_inserted_once_at_the_cursor_when_committed = (): void => {
  const entries = merger.Merge([[parser.ParseLine('か /蚊;昆虫/科;学科/')]])
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', entries, preferences)
  const editor = registration_editor.Editor.new(ime)
  editor.InsertLiteral('前後')
  editor.Move(-1)
  editor.Append(ime.Feed('K'))
  editor.Append(ime.Feed('a'))
  editor.Append(ime.StartConversion(entries, preferences))
  assert.equals(editor.GetText(), '前後')
  editor.Append([ime.NextCandidate()])
  editor.Commit()
  assert.equals(editor.GetText(), '前科後')
  assert.equals(editor.GetCursor(), 2)
  editor.Commit()
  assert.equals(editor.GetText(), '前科後')
}
