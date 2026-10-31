vim9script

import autoload 'caskk/buffer.vim' as buffer
import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/user_state.vim' as user_state
import 'caskk/dictionary.vim' as dictionary

final suite = themis#suite('buffer integration')
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

def Apply(writer: buffer.Writer, results: list<session.Result>)
  for result in results
    writer.Apply(result)
  endfor
enddef

suite.preedit_candidate_and_cancel_replace_only_the_tracked_range = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  const writer = buffer.Writer.new(number, 1, 4)
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  Apply(writer, ime.Feed('K'))
  Apply(writer, ime.Feed('a'))
  assert.equals(getbufline(number, 1, '$'), ['前か後'])
  assert.equals(writer.InPreedit(), true)
  const entries = merger.Merge([[parser.ParseLine('か /蚊/科/')]])
  Apply(writer, ime.StartConversion(entries, user_state.State.new()))
  assert.equals(getbufline(number, 1, '$'), ['前蚊後'])
  writer.Apply(ime.SelectCandidate(1))
  assert.equals(getbufline(number, 1, '$'), ['前科後'])
  writer.Apply(ime.CancelConversion())
  assert.equals(getbufline(number, 1, '$'), ['前か後'])
  Apply(writer, ime.Feed('k'))
  Apply(writer, ime.Feed('a'))
  assert.equals(getbufline(number, 1, '$'), ['前かか後'])
  Apply(writer, ime.Commit())
  assert.equals(getbufline(number, 1, '$'), ['前かか後'])
  assert.equals(writer.InPreedit(), false)
  assert.equals(writer.GetPosition().line, 1)
  assert.equals(writer.GetPosition().column, 10)
}

suite.candidate_commit_and_following_direct_text_are_not_inserted_twice = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  const writer = buffer.Writer.new(number, 1, 4)
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}, [scheme.SpecialDefinition.new(['x'], '。')]))
  Apply(writer, ime.Feed('K'))
  Apply(writer, ime.Feed('a'))
  Apply(writer, ime.StartConversion(merger.Merge([[parser.ParseLine('か /蚊/')]]), user_state.State.new()))
  Apply(writer, ime.Feed('x'))
  assert.equals(getbufline(number, 1, '$'), ['前蚊。後'])
  assert.equals(writer.InPreedit(), false)
  Apply(writer, ime.Feed('?'))
  assert.equals(getbufline(number, 1, '$'), ['前蚊。後'])
}

suite.registration_replaces_the_reading_and_commits_the_replacement = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  const writer = buffer.Writer.new(number, 1, 4)
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  Apply(writer, ime.Feed('K'))
  Apply(writer, ime.Feed('a'))
  Apply(writer, ime.StartConversion({}, user_state.State.new()))
  writer.Apply(ime.Register(dictionary.Candidate.new('蚊', [])))
  assert.equals(getbufline(number, 1, '$'), ['前蚊後'])
  assert.equals(writer.InPreedit(), false)
}

suite.okuri_cancel_and_plain_commit_keep_the_full_reading = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  const writer = buffer.Writer.new(number, 1, 4)
  const compiled = scheme.Compile({k: 'k'}, {a: 'a'}, [scheme.SpecialDefinition.new(['z', 'x'], 'い*くらい')])
  const entries = merger.Merge([[parser.ParseLine('いk /行/')]])
  const ime = session.Session.new(compiled, '', entries, user_state.State.new())
  Apply(writer, ime.Feed('Z'))
  Apply(writer, ime.Feed('X'))
  assert.equals(getbufline(number, 1, '$'), ['前行くらい後'])
  writer.Apply(ime.PreviousCandidate())
  assert.equals(getbufline(number, 1, '$'), ['前いくらい後'])
  Apply(writer, ime.Feed('k'))
  Apply(writer, ime.Feed('a'))
  assert.equals(getbufline(number, 1, '$'), ['前いくらいか後'])
  assert.equals(writer.InPreedit(), false)
}

suite.multiline_candidates_can_be_replaced_by_the_original_reading = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, ['前後', '次行'])
  const writer = buffer.Writer.new(number, 1, 4)
  const preferences = user_state.State.new()
  preferences.AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new("漢\n字", []))
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  Apply(writer, ime.Feed('K'))
  Apply(writer, ime.Feed('a'))
  Apply(writer, ime.StartConversion({}, preferences))
  assert.equals(getbufline(number, 1, '$'), ['前漢', '字後', '次行'])
  assert.equals(writer.GetPosition().line, 2)
  assert.equals(writer.GetPosition().column, 4)
  writer.Apply(ime.CancelConversion())
  assert.equals(getbufline(number, 1, '$'), ['前か後', '次行'])
  assert.equals(writer.GetPosition().line, 1)
  assert.equals(writer.GetPosition().column, 7)
}

suite.external_changes_to_preedit_are_rejected_without_overwriting_them = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  const writer = buffer.Writer.new(number, 1, 4)
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}))
  Apply(writer, ime.Feed('K'))
  Apply(writer, ime.Feed('a'))
  setbufline(number, 1, '前外後')
  var caught = ''
  try
    Apply(writer, ime.Commit())
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: tracked preedit text was changed externally')
  assert.equals(getbufline(number, 1, '$'), ['前外後'])
}

suite.unmodifiable_buffers_are_rejected_before_any_edit = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  const writer = buffer.Writer.new(number, 1, 4)
  setbufvar(number, '&modifiable', false)
  const ime = session.Session.new(scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['x'], '字')]))
  var caught = ''
  try
    Apply(writer, ime.Feed('x'))
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: target buffer is not modifiable')
  assert.equals(getbufline(number, 1, '$'), ['前後'])
  assert.equals(writer.GetPosition().column, 4)
}

suite.empty_preedit_can_commit_at_the_end_of_a_multibyte_line = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前')
  const writer = buffer.Writer.new(number, 1, 4)
  const ime = session.Session.new(scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['x'], ''), scheme.SpecialDefinition.new(['y'], '字'),
  ]))
  Apply(writer, ime.Feed('X'))
  assert.equals(writer.InPreedit(), true)
  assert.equals(getbufline(number, 1, '$'), ['前'])
  Apply(writer, ime.Commit())
  assert.equals(writer.InPreedit(), false)
  Apply(writer, ime.Feed('y'))
  assert.equals(getbufline(number, 1, '$'), ['前字'])
  assert.equals(writer.GetPosition().column, 7)
}

suite.starting_inside_a_multibyte_character_is_rejected = (): void => {
  const number = Scratch()
  defer Wipe(number)
  setbufline(number, 1, '前後')
  for column in [2, 3, 5, 6]
    var caught = ''
    try
      buffer.Writer.new(number, 1, column)
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: buffer column is not a character boundary')
    assert.equals(getbufline(number, 1, '$'), ['前後'])
  endfor
}
