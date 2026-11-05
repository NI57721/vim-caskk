vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('user state codec')
const assert = themis#helper('assert')
const HEADER = '["caskk-user-state","1"]'

def Reject(lines: list<string>)
  var caught = ''
  try
    codec.Decode(lines)
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: invalid user state:'), 0)
enddef

suite.empty_state_has_an_explicit_header = (): void => {
  assert.equals(codec.Encode(user_state.State.new().GetSnapshot()), [HEADER])
  const snapshot = codec.Decode([HEADER])
  assert.equals(snapshot.version, 1)
  assert.equals(snapshot.entries, {})
  assert.equals(snapshot.mru, {})
  assert.equals(snapshot.pinned, {})
  assert.equals(snapshot.demoted, {})
}

suite.records_preserve_entries_annotations_and_preference_order = (): void => {
  const lines = [HEADER,
    '["entry","い","く","行","移動","ゆく"]',
    '["entry","い","く","往"]',
    '["entry","い","く","逝"]',
    '["mru","い","く","逝","行"]',
    '["pin","い","く","往"]',
    '["demoted","い","く","行"]',
  ]
  const snapshot = codec.Decode(lines)
  const key = json_encode(['い', 'く'])
  assert.equals(snapshot.entries[key][0].text, '行')
  assert.equals(snapshot.entries[key][0].annotations, ['移動', 'ゆく'])
  assert.equals(snapshot.mru[key], ['逝', '行'])
  assert.equals(snapshot.pinned[key], '往')
  assert.equals(snapshot.demoted[key], ['行'])
  assert.equals(codec.Encode(snapshot), lines)
  const state = user_state.State.new()
  state.Restore(snapshot)
  const ranked = state.Rank(lookup.CreateQuery('い', 'くれば'), [])
  assert.equals(ranked[0].text, '往')
  assert.equals(ranked[1].text, '逝')
  assert.equals(ranked[2].text, '行')
  assert.equals(mapnew(state.Rank(lookup.CreateQuery('い', 'こない'), []), (_, candidate) => candidate.text),
    ['行', '往', '逝'])
}

suite.encoding_preserves_special_characters_and_empty_okuri = (): void => {
  const state = user_state.State.new()
  const query = lookup.CreateQuery('よみ', '')
  const text = "字/;\"\\\n次"
  const note = "注\t釈"
  state.AddEntry(query, dictionary.Candidate.new(text, [note]))
  const lines = codec.Encode(state.GetSnapshot())
  assert.equals(len(lines), 2)
  const restored = user_state.State.new()
  restored.Restore(codec.Decode(lines))
  const candidates = restored.Rank(query, [])
  assert.equals(candidates[0].text, text)
  assert.equals(candidates[0].annotations, [note])
}

suite.encoding_is_deterministic_across_identity_insertion_order = (): void => {
  const first = user_state.State.new()
  const second = user_state.State.new()
  for reading in ['い', 'あ']
    first.AddEntry(lookup.CreateQuery(reading, ''), dictionary.Candidate.new('字', []))
  endfor
  for reading in ['あ', 'い']
    second.AddEntry(lookup.CreateQuery(reading, ''), dictionary.Candidate.new('字', []))
  endfor
  assert.equals(codec.Encode(first.GetSnapshot()), [HEADER, '["entry","あ","","字"]', '["entry","い","","字"]'])
  assert.equals(codec.Encode(second.GetSnapshot()), codec.Encode(first.GetSnapshot()))
}

suite.missing_or_unsupported_header_is_rejected = (): void => {
  Reject([])
  Reject(['["other","1"]'])
  Reject(['["caskk-user-state","0"]'])
  Reject(['["caskk-user-state","2"]'])
  Reject(['["caskk-user-state",1]'])
  var caught = ''
  try
    codec.Encode(user_state.Snapshot.new(2, {}, {}, {}, {}))
  catch
    caught = v:exception
  endtry
  assert.equals(stridx(caught, 'caskk: invalid user state:'), 0)
}

suite.invalid_json_types_record_shapes_and_okuri_are_rejected = (): void => {
  for line in ['not json', '{}', 'null', '[]', '[1]', '["entry",{},"","字"]',
      '["entry","い","く",["字"]]', '["unknown","い",""]',
      '["entry","い","く"]', '["pin","い","く","行","往"]',
      '["mru","い"]', '["entry","い","くらい","行"]']
    Reject([HEADER, line])
  endfor
}

suite.duplicate_records_and_conflicting_tiers_are_rejected = (): void => {
  for line in ['["entry","い","く","行"]', '["mru","い","く","行"]',
      '["pin","い","く","行"]', '["demoted","い","く","行"]']
    Reject([HEADER, line, line])
  endfor
  Reject([HEADER, '["mru","い","く","行","行"]'])
  Reject([HEADER, '["demoted","い","く","行","行"]'])
  Reject([HEADER, '["pin","い","く","行"]', '["demoted","い","く","行"]'])
  Reject([HEADER, '["demoted","い","く","行"]', '["pin","い","く","行"]'])
}
