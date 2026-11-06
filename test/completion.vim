vim9script

import autoload 'caskk/completion.vim' as completion
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/index.vim' as dictionary_index
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/config.vim' as config
import 'caskk/dictionary.vim' as dictionary

final suite = themis#suite('reading completion')
const assert = themis#helper('assert')

def Entries(): dict<dictionary.Entry>
  return merger.Merge([[parser.ParseLine('かな /仮名;文字/'),
    parser.ParseLine('かなもの /金物/'), parser.ParseLine('かえる /蛙/'),
    parser.ParseLine('かなs /奏/'), parser.ParseLine('apple /林檎/')]])
enddef

suite.prefix_search_merges_sources_in_sorted_and_fallback_dictionaries = (): void => {
  const source = dictionary_index.SourceFromLines([';; okuri-ari entries.', 'かなs /奏/',
    ';; okuri-nasi entries.', 'かえる /蛙/', 'かな /仮名;文字/', 'かなもの /金物/'])
  const fallback = dictionary_index.SourceFromLines(['かな /仮名;別注/カナ/', 'か /蚊/'])
  const database = dictionary_index.Database.new([source, fallback])
  const found = database.Prefix('かな')
  assert.equals(sort(keys(found)), ['かな', 'かなs', 'かなもの'])
  assert.equals(mapnew(found['かな'].candidates, (_, c) => c.text), ['仮名', 'カナ'])
  assert.equals(found['かな'].candidates[0].annotations, ['文字', '別注'])
  assert.equals(database.Prefix('なし'), {})
}

suite.completion_has_separate_candidates_and_does_not_infer_system_okuri = (): void => {
  const preferences = user_state.State.new()
  const result = completion.Prepare(Entries(), preferences, 'かな')
  assert.equals(mapnew(result, (_, c) => c.text), ['仮名', '奏', '金物'])
  assert.equals(result[1].query.lookup_key, 'かなs')
  assert.equals(result[1].okuri, '')
  assert.equals(result[1].learnable, false)
  assert.equals(completion.Prepare(Entries(), preferences, '見つからない'), [])
}

suite.user_entries_and_ranking_use_their_own_reading_and_exact_okuri = (): void => {
  const preferences = user_state.State.new()
  const query = lookup.CreateQuery('かなもの', '')
  preferences.AddEntry(query, dictionary.Candidate.new('かな物', []))
  preferences.Pin(query, 'かな物')
  const exact = lookup.CreateQuery('かな', 'し')
  preferences.AddEntry(exact, dictionary.Candidate.new('奏', []))
  const candidates = completion.Prepare(Entries(), preferences, 'かな')
  assert.equals(index(mapnew(candidates, (_, c) => c.text), '奏し') >= 0, true)
  final metal: list<completion.Candidate> = copy(candidates)
  filter(metal, (_, c) => c.query.reading ==# 'かなもの')
  assert.equals(mapnew(metal, (_, c) => c.text), ['かな物', '金物'])
  const okuri = completion.Prepare(Entries(), preferences, 'かな', 'して')
  assert.equals(mapnew(okuri, (_, c) => c.text), ['奏して'])
}

suite.settings_validate_minimum_length_and_action = (): void => {
  config.ConfigureIncrementally({completion_min_length: 3, mappings: {"\<Tab>": 'ShowCompletion'}})
  assert.equals(config.GetInput().completion_min_length, 3)
  for value in [0, -1, true, '2']
    var reason = ''
    try
      config.ConfigureIncrementally({completion_min_length: value})
    catch
      reason = v:exception
    endtry
    assert.equals(reason, 'caskk: invalid configuration: completion_min_length must be a positive number')
  endfor
  config.ConfigureIncrementally({})
  assert.equals(config.GetInput().completion_min_length, 2)
}

suite.session_selection_commits_directly_and_learns_only_on_accept = (): void => {
  const preferences = user_state.State.new()
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', Entries(), preferences, 'かな')
  assert.equals(ime.ShowCompletion(2), true)
  assert.equals(ime.InCandidate(), false)
  assert.equals(ime.InCompletion(), true)
  assert.equals(ime.GetSnapshot().reading, 'かな')
  assert.equals(ime.GetCompletionInfo().candidates[0].text, '仮名')
  ime.MoveCompletion(1)
  ime.MoveCompletion(1)
  assert.equals(ime.GetCompletionInfo().selected_index, 2)
  assert.equals(preferences.Revision(), 0)
  const accepted = ime.Commit()
  assert.equals(accepted[-1].text, '金物')
  assert.equals(accepted[-1].commit_preedit, true)
  assert.equals(accepted[-1].replace_preedit, true)
  assert.equals(ime.GetSnapshot().in_preedit, false)
  assert.equals(ime.InCompletion(), false)
  assert.equals(preferences.GetSnapshot().mru[json_encode(['かなもの', ''])], ['金物'])
}

suite.minimum_length_pending_input_cancel_and_normal_input_leave_reading_intact = (): void => {
  const ime = session.Session.new(scheme.Compile({k: 'k'}, {a: 'a'}), '', Entries(), null_object, 'か')
  assert.equals(ime.ShowCompletion(2), false)
  ime.Feed('k')
  assert.equals(ime.ShowCompletion(1), false)
  ime.BackspacePending()
  assert.equals(ime.ShowCompletion(1), true)
  ime.CancelCompletion()
  assert.equals(ime.GetSnapshot().reading, 'か')
  assert.equals(ime.InCompletion(), false)
  ime.ShowCompletion(1)
  ime.Feed('a')
  assert.equals(ime.InCompletion(), false)
  assert.equals(ime.GetSnapshot().reading, 'かあ')
}

suite.prefix_search_handles_descending_okuri_gaps_duplicates_and_bad_rows = (): void => {
  const source = dictionary_index.SourceFromLines([';; okuri-ari entries.',
    'かなものk /金/', ';; gap', '', 'かなs /奏/', 'かなs /', 'かなs /叶/', 'かk /書/',
    ';; okuri-nasi entries.', 'か /蚊/', 'かな /仮名/', '', 'かなもの /金物/', 'き /木/'])
  const database = dictionary_index.Database.new([source])
  assert.equals(sort(keys(database.Prefix('かな'))), ['かな', 'かなs', 'かなもの', 'かなものk'])
  assert.equals(mapnew(database.Prefix('かな')['かなs'].candidates, (_, c) => c.text), ['奏', '叶'])
  assert.equals(database.Prefix('く'), {})
  assert.equals(database.Prefix(''), {})
}

suite.user_only_and_abbreviation_completion_preserve_known_readings = (): void => {
  const preferences = user_state.State.new()
  preferences.AddEntry(lookup.CreateQuery('ひみつ', ''), dictionary.Candidate.new('秘密', []))
  const hidden = completion.Prepare({}, preferences, 'ひみ')
  assert.equals(hidden[0].text, '秘密')
  assert.equals(hidden[0].query.reading, 'ひみつ')
  const abbreviation = completion.Prepare(Entries(), preferences, 'app')
  assert.equals(abbreviation[0].text, '林檎')
  assert.equals(abbreviation[0].query.reading, 'apple')
  assert.equals(abbreviation[0].learnable, true)
}

suite.coarse_okuri_acceptance_does_not_fabricate_exact_history = (): void => {
  const preferences = user_state.State.new()
  const entries = merger.Merge([[parser.ParseLine('かなs /奏/')]])
  const ime = session.Session.new(scheme.Compile({}, {a: 'a'}), '', entries, preferences, 'かな')
  ime.ShowCompletion(2)
  assert.equals(ime.Commit()[-1].text, '奏')
  assert.equals(preferences.GetSnapshot().mru, {})
}

suite.unknown_system_okuri_does_not_borrow_plain_reading_preferences = (): void => {
  const preferences = user_state.State.new()
  preferences.Demote(lookup.CreateQuery('かな', ''), '奏')
  const candidates = completion.Prepare(Entries(), preferences, 'かな')
  const coarse = candidates[1]
  assert.equals(coarse.query.lookup_key, 'かなs')
  assert.equals(coarse.tier, 'normal')
}

suite.prefix_search_respects_euc_jp_order = (): void => {
  const database = dictionary_index.Database.new([dictionary_index.SourceFromLines([
    ';; okuri-ari entries.', ';; okuri-nasi entries.',
    'ほ /歩/', 'まーじゃん /麻雀/', 'まーじゃんよう /麻雀用/',
    'まいかい /毎回/', 'まいにち /毎日/', 'まんず /先ず/', 'も /藻/'], 'euc-jp')])
  assert.equals(sort(keys(database.Prefix('まい'))), ['まいかい', 'まいにち'])
  assert.equals(sort(keys(database.Prefix('まー'))), ['まーじゃん', 'まーじゃんよう'])
}

suite.small_tsu_okuri_uses_the_configured_dictionary_consonant = (): void => {
  const entries = merger.Merge([[parser.ParseLine('かt /勝/'), parser.ParseLine('かx /買/')]])
  const preferences = user_state.State.new()
  assert.equals(completion.Prepare(entries, preferences, 'か', 'って', null_object, false)[0].text, '買って')
  assert.equals(completion.Prepare(entries, preferences, 'か', 'って', null_object, true)[0].text, '勝って')
  preferences.AddEntry(lookup.CreateQuery('か', 'っ', false), dictionary.Candidate.new('買', []))
  assert.equals(completion.Prepare({}, preferences, 'か', '', null_object, false)[0].text, '買っ')
}
