vim9script
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk.vim' as Caskk
import autoload 'caskk/user_state/runtime.vim' as runtime
import autoload 'caskk/dictionary/loader.vim' as loader
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/user_state.vim' as state
import autoload 'caskk/user_state/codec.vim' as codec
import autoload 'caskk/session.vim' as session
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/registration/text.vim' as registration_text
final suite = themis#suite('experimental verbs')
const assert = themis#helper('assert')
suite.ichidan_stem_is_not_rewritten = (): void => {
  const entry = parser.ParseLine('たべ /食べ;@verb-1/')
  const preferences = state.State.new()
  for suffix in ['る', 'れ', 'ろ', 'よ', 'な', 'ま', 'た', 'て', 'ら', 'さ']
    const prepared = conversion.Prepare({'たべ': entry}, preferences, 'たべ', suffix)
    assert.equals(len(prepared.candidates), 1)
    const selection = conversion.Selection.new(prepared, preferences)
    assert.equals(selection.CurrentText(), '食べ' .. suffix .. '')
    assert.equals(selection.Commit(), '食べ' .. suffix)
  endfor
  assert.equals(empty(preferences.GetSnapshot().mru), false)
}

suite.types_filter_candidates_and_preserve_ordinary_duplicates = (): void => {
  const stem = parser.ParseLine('か /書;説明 @verb-5-k @verb-bungo-4-k/架;@verb-unknown/描;@verb-5-k-extra/')
  const normal = parser.ParseLine('かk /書/')
  const preferences = state.State.new()
  const prepared = conversion.Prepare({'か': stem, 'かk': normal}, preferences, 'か', 'く')
  assert.equals(mapnew(prepared.candidates, (_, item) => item.text), ['書', '書'])
  assert.equals(prepared.experimental_count, 1)
  assert.equals(conversion.Prepare({'か': stem}, preferences, 'か', 'な').candidates, [])
  const selected = conversion.Selection.new(prepared, preferences)
  assert.equals(selected.TogglePin(), 'pinned')
  assert.equals(selected.ToggleDemote(), 'demoted')
  selected.Commit()
  assert.equals(preferences.GetSnapshot().mru, {})
  const ordinary = conversion.Selection.new(prepared, preferences)
  ordinary.Next()
  assert.equals(ordinary.CurrentText(), '書く')
  preferences.Reset(prepared.query, prepared.candidates[0].text)
  ordinary.Commit()
  assert.equals(empty(preferences.GetSnapshot().mru), false)
}

suite.godan_sound_changes_and_irregular_types_are_distinct = (): void => {
  for [tag, allowed, rejected] in [
    ['5-k', 'い', 'っ'], ['5-k-iku', 'っ', 'い'], ['5-k-yuku', 'っ', 'い'],
    ['5-g', 'い', 'っ'], ['5-m', 'ん', 'っ'], ['5-r-aru', 'い', 'ん'],
    ['5-w', 'っ', 'ん'], ['5-w-tou', 'う', 'っ'],
    ['1-kureru', 'れ', 'ろ'], ['1', 'ろ', 'ぱ'],
    ['henkaku-k', 'こ', 'せ'], ['henkaku-k', 'る', 'ぱ'], ['henkaku-k', 'た', 'ぱ'], ['henkaku-s', 'せ', 'こ'], ['henkaku-z', 'じ', 'し'],
    ['bungo-2-kami-k', 'き', 'け'], ['bungo-2-shimo-k', 'け', 'き'],
    ['bungo-henkaku-n', 'ぬ', 'る'], ['bungo-henkaku-r', 'り', 'ぬ']]
    const entry = parser.ParseLine('よ /語;@verb-' .. tag .. '/')
    const entries = {'よ': entry}
    assert.equals(len(conversion.Prepare(entries, state.State.new(), 'よ', allowed).candidates), 1, tag)
    assert.equals(conversion.Prepare(entries, state.State.new(), 'よ', rejected).candidates, [], tag)
  endfor
}

suite.adjective_and_verb_markers_merge_without_changing_stems = (): void => {
  const entry = parser.ParseLine('よ /良;@adj @verb-5-m/')
  const prepared = conversion.Prepare({'よ': entry}, state.State.new(), 'よ', 'み')
  assert.equals(len(prepared.candidates), 1)
  const selected = conversion.Selection.new(prepared, state.State.new())
  assert.equals(selected.CurrentText(), '良み')
  assert.equals(selected.Commit(), '良み')
}

suite.indexed_euc_jp_and_user_stems_keep_annotations = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(mapnew([';; okuri-ari entries.', ';; okuri-nasi entries.',
    'き /切;@verb-5-r/着;@verb-1/',
    'たべ /食べ;説明 @verb-1/'],
    (_, line) => iconv(line, 'utf-8', 'euc-jp')), path)
  const database = loader.Open([loader.Source.new(path, 'euc-jp')])
  const preferences = state.State.new()
  const prepared = conversion.Prepare({}, preferences, 'たべ', 'る', true, database)
  assert.equals(prepared.TextAt(0), '食べる')
  assert.equals(prepared.candidates[0].annotations, ['説明 @verb-1'])
  const homonyms = conversion.Prepare({}, preferences, 'き', 'ら', true, database)
  assert.equals(mapnew(homonyms.candidates, (_, item) => item.text), ['切', '着'])
  preferences.AddEntry(lookup.CreateQuery('たべ', ''), parser.ParseLine('たべ /喰べ;@verb-1/').candidates[0])
  const registered = conversion.Prepare({}, preferences, 'たべ', 'な')
  assert.equals(registered.TextAt(0), '喰べな')
}

suite.all_57_types_accept_their_terminal_connection_and_reject_unrelated_kana = (): void => {
  const cases = [
    ['5-k', 'く'],
    ['5-k-iku', 'く'],
    ['5-k-yuku', 'く'],
    ['5-g', 'ぐ'],
    ['5-s', 'す'],
    ['5-t', 'つ'],
    ['5-n', 'ぬ'],
    ['5-b', 'ぶ'],
    ['5-m', 'む'],
    ['5-r', 'る'],
    ['5-r-aru', 'る'],
    ['5-w', 'う'],
    ['5-w-tou', 'う'],
    ['1', 'る'],
    ['1-kureru', 'る'],
    ['1-uru', 'る'],
    ['henkaku-k', 'く'],
    ['henkaku-s', 'す'],
    ['henkaku-z', 'ず'],
    ['bungo-4-k', 'く'],
    ['bungo-4-g', 'ぐ'],
    ['bungo-4-s', 'す'],
    ['bungo-4-t', 'つ'],
    ['bungo-4-h-u', 'う'],
    ['bungo-4-h-hu', 'ふ'],
    ['bungo-4-b', 'ぶ'],
    ['bungo-4-m', 'む'],
    ['bungo-4-r', 'る'],
    ['bungo-2-kami-k', 'く'],
    ['bungo-2-kami-g', 'ぐ'],
    ['bungo-2-kami-t', 'つ'],
    ['bungo-2-kami-d', 'づ'],
    ['bungo-2-kami-h', 'ふ'],
    ['bungo-2-kami-b', 'ぶ'],
    ['bungo-2-kami-m', 'む'],
    ['bungo-2-kami-y', 'ゆ'],
    ['bungo-2-kami-r', 'る'],
    ['bungo-2-shimo-a', 'う'],
    ['bungo-2-shimo-k', 'く'],
    ['bungo-2-shimo-g', 'ぐ'],
    ['bungo-2-shimo-s', 'す'],
    ['bungo-2-shimo-z', 'ず'],
    ['bungo-2-shimo-t', 'つ'],
    ['bungo-2-shimo-d-zu', 'ず'],
    ['bungo-2-shimo-d-du', 'づ'],
    ['bungo-2-shimo-n', 'ぬ'],
    ['bungo-2-shimo-h', 'ふ'],
    ['bungo-2-shimo-b', 'ぶ'],
    ['bungo-2-shimo-m', 'む'],
    ['bungo-2-shimo-y', 'ゆ'],
    ['bungo-2-shimo-r', 'る'],
    ['bungo-2-shimo-w', 'う'],
    ['bungo-henkaku-k', 'く'],
    ['bungo-henkaku-s', 'す'],
    ['bungo-henkaku-z', 'ず'],
    ['bungo-henkaku-n', 'ぬ'],
    ['bungo-henkaku-r', 'り'],
  ]
  assert.equals(len(cases), 57)
  for [tag, ending] in cases
    const entry = parser.ParseLine('よ /語;@verb-' .. tag .. '/')
    const preferences = state.State.new()
    const entries = {'よ': entry}
    const prepared = conversion.Prepare(entries, preferences, 'よ', ending)
    assert.equals(len(prepared.candidates), 1, tag)
    assert.equals(prepared.TextAt(0), '語' .. ending, tag)
    assert.equals(conversion.Prepare(entries, preferences, 'よ', 'ぱ').candidates, [], tag)
  endfor
}

suite.bare_stems_are_hidden_but_independent_plain_sources_survive = (): void => {
  const tagged = parser.ParseLine('か /書;@verb-5-k/')
  const preferences = state.State.new()
  assert.equals(conversion.Prepare({'か': tagged}, preferences, 'か').candidates, [])
  const plain = parser.ParseLine('か /書;通常/')
  for sources in [[[tagged], [plain]], [[plain], [tagged]]]
    const combined = merger.Merge(sources)
    assert.equals(len(conversion.Prepare(combined, preferences, 'か').candidates), 1)
  endfor
}

suite.ordinary_conversion_hides_nonstandalone_tags_from_merged_sources = (): void => {
  const plain = dict_index.SourceFromLines(['き /聞/'])
  const tagged = dict_index.SourceFromLines(['き /聞;@verb-5-k/'])
  const combined = dict_index.SourceFromLines(['き /聞/', 'き /聞;@verb-5-k/'])
  const preferences = state.State.new()
  for sources in [[plain, tagged], [tagged, plain], [combined]]
    const database = dict_index.Database.new(sources)
    const ordinary = conversion.Prepare({}, preferences, 'き', '', true, database)
    assert.equals(mapnew(ordinary.candidates, (_, candidate) => candidate.text), ['聞'])
    assert.equals(ordinary.candidates[0].annotations, [])
    assert.equals(ordinary.candidates[0].has_plain_source, true)
    const stem = conversion.Prepare({}, preferences, 'き', 'く', true, database)
    assert.equals(len(stem.candidates), 1)
    assert.equals(stem.DisplayAt(0), '聞く［verb］')
    assert.equals(stem.candidates[0].annotations, ['@verb-5-k'])
  endfor
}

suite.okuri_nashi_prefers_one_ordinary_candidate_over_the_same_verb_stem = (): void => {
  const plain = dict_index.SourceFromLines(['とじ /戸締め/綴じ/', 'とじr /綴じ/'])
  const tagged = dict_index.SourceFromLines(['とじ /綴じ;@verb-1/閉じ;@verb-1/'])
  for sources in [[plain, tagged], [tagged, plain]]
    const database = dict_index.Database.new(sources)
    const preferences = state.State.new()
    const prepared = conversion.Prepare({}, preferences, 'とじ', '', true, database)
    assert.equals(sort(mapnew(prepared.candidates, (_, candidate) => candidate.text)), ['戸締め', '綴じ', '閉じ'])
    const index_of_verb = index(mapnew(prepared.candidates, (_, candidate) => candidate.text), '綴じ')
    const selection = conversion.Selection.new(prepared, preferences)
    selection.Select(index_of_verb)
    const stem_index = index(mapnew(prepared.candidates, (_, candidate) => candidate.text), '閉じ')
    assert.equals(prepared.DisplayAt(stem_index), '閉じ［verb］')
    assert.equals(selection.GetInfo().text, '綴じ')
    assert.equals(selection.GetInfo().annotations, ['@verb-1'])
    assert.equals(selection.Commit(), '綴じ')

    const learned = conversion.Prepare({}, preferences, 'とじ', '', true, database)
    assert.equals(learned.DisplayAt(0), '綴じ')
    const ranked = conversion.Selection.new(learned, preferences)
    assert.equals(ranked.TogglePin(), 'pinned')
    assert.equals(conversion.Prepare({}, preferences, 'とじ', '', true, database).DisplayAt(0), '綴じ')
    assert.equals(ranked.ToggleDemote(), 'demoted')
    const demoted = conversion.Prepare({}, preferences, 'とじ', '', true, database)
    assert.equals(demoted.DisplayAt(len(demoted.candidates) - 1), '綴じ')

    const inflected = conversion.Prepare({}, state.State.new(), 'とじ', 'る', true, database)
    assert.equals(sort(mapnew(inflected.candidates, (i, _) => inflected.DisplayAt(i))),
      ['綴じる', '綴じる［verb］', '閉じる［verb］'])
  endfor
}

suite.ordinary_conversion_keeps_other_annotation_tokens = (): void => {
  const annotation = '@verb-5-k;説明;@verb-5-k ; @adj @verb-unknown @verb-1;@verb-5-k @verb-5-g'
  const database = dict_index.Database.new([dict_index.SourceFromLines([
    'き /聞/', 'き /聞;' .. annotation .. '/', 'とじ /綴じ;@verb-1/'])])
  const preferences = state.State.new()
  const ordinary = conversion.Prepare({}, preferences, 'き', '', true, database)
  assert.equals(ordinary.DisplayAt(0), '聞')
  assert.equals(ordinary.candidates[0].annotations, ['説明;@adj @verb-unknown @verb-1'])
  const adjective = conversion.Prepare({}, preferences, 'き', 'い', true, database)
  assert.equals(adjective.DisplayAt(0), '聞い［adj,verb］')
  assert.equals(adjective.candidates[0].annotations, [annotation])
  const ichidan = conversion.Prepare({}, preferences, 'とじ', '', true, database)
  assert.equals(ichidan.DisplayAt(0), '綴じ［verb］')
  assert.equals(ichidan.candidates[0].annotations, ['@verb-1'])
}

suite.plain_user_and_indexed_sources_survive_snapshot_copying = (): void => {
  const path = tempname()
  defer delete(path)
  writefile(mapnew([';; okuri-ari entries.', ';; okuri-nasi entries.',
    'か /書;@verb-5-k/'], (_, line) => iconv(line, 'utf-8', 'euc-jp')), path)
  const database = loader.Open([loader.Source.new(path, 'euc-jp')])
  const preferences = state.State.new()
  assert.equals(conversion.Prepare({}, preferences, 'か', '', true, database).candidates, [])
  preferences.AddEntry(lookup.CreateQuery('か', ''), parser.ParseLine('か /書/').candidates[0])
  const copied = state.State.new()
  copied.Restore(preferences.GetSnapshot())
  const ordinary = conversion.Prepare({}, copied, 'か', '', true, database)
  assert.equals(len(ordinary.candidates), 1)
  assert.equals(ordinary.candidates[0].annotations, [])
  const unknown = parser.ParseLine('か /書;@verb-unknown/')
  assert.equals(len(conversion.Prepare({'か': unknown}, state.State.new(), 'か').candidates), 1)
  const both = parser.ParseLine('か /書;@adj @verb-5-k/')
  assert.equals(conversion.Prepare({'か': both}, state.State.new(), 'か').candidates, [])
}

suite.experimental_ranking_tracks_markers_and_explicit_choices = (): void => {
  const entry = parser.ParseLine('かな /仮名;@adj/叶;@verb-5-w/適;@adj @verb-5-w/')
  const entries = {'かな': entry}
  const preferences = state.State.new()
  const initial = conversion.Prepare(entries, preferences, 'かな', 'い')
  const selected = conversion.Selection.new(initial, preferences)
  selected.Select(1)
  selected.Commit()
  const learned = conversion.Prepare(entries, preferences, 'かな', 'い')
  assert.equals(learned.DisplayAt(0), '叶い［verb］')
  preferences.Pin(learned.PreferenceQuery(0), '適')
  const pinned = conversion.Prepare(entries, preferences, 'かな', 'い')
  assert.equals(pinned.DisplayAt(0), '適い［adj,verb］')
  const pin_selection = conversion.Selection.new(pinned, preferences)
  assert.equals(pin_selection.GetInfo().tier, 'pinned')
  pin_selection.Commit()
  assert.equals(conversion.Prepare(entries, preferences, 'かな', 'い').DisplayAt(0), '適い［adj,verb］')
  preferences.Demote(learned.PreferenceQuery(0), '適')
  const demoted = conversion.Prepare(entries, preferences, 'かな', 'い')
  assert.equals(demoted.DisplayAt(2), '適い［adj,verb］')
  assert.equals(conversion.Selection.new(demoted, preferences).GetCandidatesInfo().candidates[2].tier, 'demoted')
}

suite.stem_preferences_are_shared_across_okuri_but_not_ordinary_candidates = (): void => {
  const entries = merger.Merge([[parser.ParseLine('か /書;@verb-5-k/描;@verb-5-k/'),
    parser.ParseLine('かk /書/描/')]])
  const preferences = state.State.new()
  const first = conversion.Prepare(entries, preferences, 'か', 'く')
  const selected = conversion.Selection.new(first, preferences)
  selected.Select(3)
  selected.Commit()
  const other = conversion.Prepare(entries, preferences, 'か', 'い')
  assert.equals(other.DisplayAt(0), '描い［verb］')
  const ordinary = conversion.Selection.new(conversion.Prepare(entries, preferences, 'か', 'く'), preferences)
  ordinary.Select(1)
  assert.equals(ordinary.CurrentText(), '書く')
  const pin = conversion.Selection.new(other, preferences)
  pin.TogglePin()
  const negative = conversion.Prepare(entries, preferences, 'か', 'か')
  assert.equals(conversion.Selection.new(negative, preferences).GetInfo().tier, 'pinned')
  pin.ToggleDemote()
  const demoted = conversion.Prepare(entries, preferences, 'か', 'け')
  assert.equals(demoted.DisplayAt(len(demoted.candidates) - 1), '描け［verb］')
}

suite.standalone_complete_forms_are_exceptions_to_bare_stem_suppression = (): void => {
  for [reading, text, tag] in [
    ['くれ', '呉れ', '1-kureru'], ['みてくれ', '見て呉れ', '1-kureru'],
    ['こ', '来', 'bungo-henkaku-k'], ['く', '来', 'bungo-henkaku-k'],
    ['す', '為', 'bungo-henkaku-s'], ['ず', 'ず', 'bungo-henkaku-z'],
    ['あり', '有り', 'bungo-henkaku-r'], ['いぬ', '往ぬ', 'bungo-henkaku-n']]
    const entry = parser.ParseLine(reading .. ' /' .. text .. ';@verb-' .. tag .. '/')
    const prepared = conversion.Prepare({[reading]: entry}, state.State.new(), reading)
    assert.equals(prepared.experimental_count, 1, reading)
    const selected = conversion.Selection.new(prepared, state.State.new())
    assert.equals(selected.CurrentText(), text .. '')
    assert.equals(selected.Commit(), text)
  endfor
  for [reading, tag] in [['か', '5-k'], ['こ', 'henkaku-k'], ['し', 'bungo-henkaku-n']]
    const entry = parser.ParseLine(reading .. ' /語;@verb-' .. tag .. '/')
    assert.equals(conversion.Prepare({[reading]: entry}, state.State.new(), reading).candidates, [], reading)
  endfor
}

suite.annotated_user_stems_registered_with_okuri_apply_to_other_endings = (): void => {
  const preferences = state.State.new()
  preferences.AddEntry(lookup.CreateQuery('たべ', 'る'),
    parser.ParseLine('たべ /食べ;説明 @verb-1/').candidates[0])
  const restored = state.State.new()
  restored.Restore(codec.Decode(codec.Encode(preferences.GetSnapshot())))
  for suffix in ['る', 'な', 'た']
    const prepared = conversion.Prepare({}, restored, 'たべ', suffix)
    assert.equals(prepared.experimental_count, 1)
    assert.equals(prepared.DisplayAt(index(prepared.experimental_flags, true)), '食べ' .. suffix .. '［verb］')
  endfor
  assert.equals(conversion.Prepare({}, restored, 'たべ', 'あ').experimental_count, 0)
}


suite.annotated_okuri_registration_is_available_as_a_verb_stem = (): void => {
  const preferences = state.State.new()
  const compiled = scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['x'], 'たべ'),
    scheme.SpecialDefinition.new(['y'], 'る'),
  ])
  const ime = session.Session.new(compiled, '', {}, preferences)
  ime.Feed('X')
  const requested = ime.Feed('Y')
  assert.equals(requested[-1].registration_requested, true)
  const registered = ime.Register(registration_text.Parse('食べ;@verb-1'))
  assert.equals(registered.text, '食べる')
  const prepared = conversion.Prepare({}, preferences, 'たべ', 'な')
  assert.equals(prepared.DisplayAt(0), '食べな［verb］')
  assert.equals(preferences.GetSnapshot().entries[json_encode(['たべ', 'る'])][0].annotations,
    ['@verb-1'])
}

suite.selection_returns_plain_text_but_popup_info_keeps_the_marker = (): void => {
  const entries = {'か': parser.ParseLine('か /書;@verb-5-k/描;@verb-5-k/')}
  const preferences = state.State.new()
  const prepared = conversion.Prepare(entries, preferences, 'か', 'く')
  const selected = conversion.Selection.new(prepared, preferences)
  assert.equals(selected.CurrentText(), '書く')
  assert.equals(selected.Select(1), '描く')
  assert.equals(selected.GetInfo().text, '描く［verb］')
  assert.equals(selected.GetCandidatesInfo().candidates[0].text, '書く［verb］')
}


suite.iu_stem_accepts_sokuon_from_system_and_user_entries = (): void => {
  const entry = parser.ParseLine('い /言;@verb-5-w/')
  for from_user in [false, true]
    const preferences = state.State.new()
    if from_user
      preferences.AddEntry(lookup.CreateQuery('い', 'う'), entry.candidates[0])
    endif
    for suffix in ['っ', 'った', 'って', 'う', 'うて']
      const prepared = conversion.Prepare(from_user ? {} : {'い': entry}, preferences, 'い', suffix)
      assert.equals(prepared.experimental_count, 1)
      assert.equals(prepared.TextAt(0), '言' .. suffix)
      assert.equals(prepared.DisplayAt(index(prepared.experimental_flags, true)), '言' .. suffix .. '［verb］')
    endfor
  endfor
}

suite.modified_i_then_l_selects_itta_without_marking_buffer_text = (): void => {
  const compiled = scheme.Compile({l: 'T'}, {i: 'i'})
  const entries = {'い': parser.ParseLine('い /言;@verb-5-w/')}
  const ime = session.Session.new(compiled, '', entries)
  ime.Feed('I')
  const results = ime.Feed('L')
  assert.equals(results[-1].in_candidate, true)
  assert.equals(results[-1].text, '言っ')
  assert.equals(ime.GetCandidatesInfo().candidates[0].text, '言っ［verb］')
}

suite.user_stem_can_be_deleted_from_a_different_ending = (): void => {
  for tag in ['@verb-5-k', '@adj']
    const preferences = state.State.new()
    for suffix in ['', 'か', 'け']
      preferences.AddEntry(lookup.CreateQuery('か', suffix),
        registration_text.Parse('書;' .. tag))
    endfor
    preferences.AddEntry(lookup.CreateQuery('か', 'こ'), registration_text.Parse('書'))
    preferences.AddEntry(lookup.CreateQuery('べつ', ''), registration_text.Parse('書;' .. tag))
    const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['x'], 'く')])
    const ime = session.Session.new(compiled, '', {}, preferences, 'か')
    ime.Feed('X')
    assert.equals(ime.InCandidate(), true)
    ime.SelectCandidate(index(ime.GetCandidates().experimental_flags, true))
    assert.equals(ime.CanDeleteUserEntry(), true)
    ime.DeleteUserEntry()
    assert.equals(ime.InCandidate(), true)
    assert.equals(ime.GetCandidatesInfo().candidates[0].text, '書く')
    assert.equals(ime.GetSnapshot().reading, 'か')
    assert.equals(ime.GetSnapshot().okuri, 'く')
    const entries = preferences.GetSnapshot().entries
    assert.equals(len(entries), 2)
    assert.equals(entries[json_encode(['か', 'こ'])][0].annotations, [])
    assert.equals(entries[json_encode(['べつ', ''])][0].text, '書')
  endfor
}

suite.deleting_a_registered_stem_preserves_its_system_source = (): void => {
  const preferences = state.State.new()
  const entries = {'か': parser.ParseLine('か /書;@verb-5-k/')}
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['x'], 'く')])
  const ime = session.Session.new(compiled, '', entries, preferences, 'か')
  ime.Feed('X')
  assert.equals(ime.CanDeleteUserEntry(), false)
  preferences.AddEntry(lookup.CreateQuery('か', 'け'), entries['か'].candidates[0])
  assert.equals(ime.CanDeleteUserEntry(), true)
  const removed = ime.DeleteUserEntry()
  assert.equals(preferences.GetSnapshot().entries, {})
  assert.equals(removed.text, '書く')
  assert.equals(ime.InCandidate(), true)
  assert.equals(ime.CanDeleteUserEntry(), false)
}


suite.yuu_stem_accepts_sokuon_from_system_and_user_entries = (): void => {
  const entry = parser.ParseLine('ゆ /言;@verb-5-w/')
  for from_user in [false, true]
    const preferences = state.State.new()
    if from_user
      preferences.AddEntry(lookup.CreateQuery('ゆ', 'う'), entry.candidates[0])
    endif
    for suffix in ['っ', 'った', 'って', 'う', 'うて']
      const prepared = conversion.Prepare(from_user ? {} : {'ゆ': entry}, preferences, 'ゆ', suffix)
      assert.equals(prepared.experimental_count, 1)
      assert.equals(prepared.TextAt(0), '言' .. suffix)
      assert.equals(prepared.DisplayAt(index(prepared.experimental_flags, true)), '言' .. suffix .. '［verb］')
    endfor
  endfor
}

suite.yu_sokuon_input_selects_itta = (): void => {
  const compiled = scheme.Compile({l: 'T'}, {}, [scheme.SpecialDefinition.new(['y'], 'ゆ')])
  const entries = {'ゆ': parser.ParseLine('ゆ /言;@verb-5-w/')}
  const ime = session.Session.new(compiled, '', entries)
  ime.Feed('Y')
  const results = ime.Feed('L')
  assert.equals(results[-1].in_candidate, true)
  assert.equals(results[-1].text, '言っ')
  assert.equals(ime.GetCandidatesInfo().candidates[0].text, '言っ［verb］')
}


suite.ichidan_stems_convert_without_okuri = (): void => {
  for [reading, text, tag] in [
    ['あけ', '開け', '1'], ['たべ', '食べ', '1'], ['み', '見', '1']]
    const entry = parser.ParseLine(reading .. ' /' .. text .. ';@verb-' .. tag .. '/')
    const preferences = state.State.new()
    const ime = session.Session.new(scheme.Compile({}, {}), '', {}, preferences, reading)
    const result = ime.StartConversion({[reading]: entry}, preferences)[0]
    assert.equals(result.in_candidate, true, reading)
    assert.equals(result.text, text, reading)
    assert.equals(ime.GetCandidatesInfo().candidates[0].text, text .. '［verb］', reading)
  endfor
}

import 'caskk/verb_tags.vim' as verb_tags

suite.ichidan_stems_accept_chau_contractions = (): void => {
  for tag in keys(verb_tags.ENDINGS)
    if index(['@verb-1', '@verb-1-kureru'], tag) < 0
      continue
    endif
    const entries = {'たべ': parser.ParseLine('たべ /食べ;' .. tag .. '/')}
    for okuri in ['ちゃう', 'ちゃった', 'ちゃって', 'ちゃわない']
      const prepared = conversion.Prepare(entries, state.State.new(), 'たべ', okuri)
      assert.equals(len(prepared.candidates), 1, tag .. ': ' .. okuri)
      assert.equals(prepared.DisplayAt(0), '食べ' .. okuri .. '［verb］')
    endfor
  endfor
}

suite.modified_chau_input_converts_the_registered_stem = (): void => {
  const compiled = scheme.Compile({}, {}, [
    scheme.SpecialDefinition.new(['x'], 'たべ'),
    scheme.SpecialDefinition.new(['y'], 'ちゃう'),
  ])
  const ime = session.Session.new(compiled, '', {'たべ': parser.ParseLine('たべ /食べ;@verb-1/')})
  ime.Feed('X')
  const results = ime.Feed('Y')
  assert.equals(results[-1].in_candidate, true)
  assert.equals(results[-1].text, '食べちゃう')
}

suite.miru_and_kuru_accept_chau_contractions = (): void => {
  for [reading, text, tag] in [['み', '見', '1'], ['き', '来', 'henkaku-k']]
    const entries = {[reading]: parser.ParseLine(reading .. ' /' .. text .. ';@verb-' .. tag .. '/')}
    for okuri in ['ちゃう', 'ちゃった', 'ちゃって', 'ちゃわない']
      const prepared = conversion.Prepare(entries, state.State.new(), reading, okuri)
      assert.equals(len(prepared.candidates), 1, text .. okuri)
      assert.equals(prepared.TextAt(0), text .. okuri)
    endfor
  endfor
}

const GODAN_CONTRACTIONS: dict<string> = {
  '5-k': 'いちゃう', '5-k-iku': 'っちゃう', '5-k-yuku': 'っちゃう',
  '5-g': 'いじゃう', '5-s': 'しちゃう', '5-t': 'っちゃう',
  '5-n': 'んじゃう', '5-b': 'んじゃう', '5-m': 'んじゃう',
  '5-r': 'っちゃう', '5-r-aru': 'っちゃう',
  '5-w': 'っちゃう', '5-w-tou': 'うちゃう',
}

suite.all_modern_verb_types_accept_shimau_contractions = (): void => {
  var tested = 0
  for tag in keys(verb_tags.ENDINGS)
    if tag =~# '^@verb-bungo-' || tag ==# '@verb-1-uru'
      continue
    endif
    const short_tag = strpart(tag, strlen('@verb-'))
    const ending = get(GODAN_CONTRACTIONS, short_tag, 'ちゃう')
    const entries = {'よ': parser.ParseLine('よ /語;' .. tag .. '/')}
    for okuri in [ending, substitute(ending, 'う$', 'った', ''), substitute(ending, 'う$', 'わない', '')]
      const prepared = conversion.Prepare(entries, state.State.new(), 'よ', okuri)
      assert.equals(len(prepared.candidates), 1, tag .. ': ' .. okuri)
      assert.equals(prepared.TextAt(0), '語' .. okuri)
    endfor
    tested += 1
  endfor
  assert.equals(tested, 18)
}


suite.tou_excludes_sokuon_and_uru_only_accepts_ru_and_re = (): void => {
  for [reading, text, tag, accepted, rejected] in [
      ['と', '問', '5-w-tou', ['う', 'うた', 'うて', 'わない'], ['っ', 'った', 'って']],
      ['う', '得', '1-uru', ['る', 'れば'], ['', 'ない', 'ます', 'た', 'て', 'ろ', 'ちゃう']],
      ['ありう', 'あり得', '1-uru', ['る', 'れば'], ['', 'ない', 'ます', 'た', 'ちゃう']]]
    const entry = parser.ParseLine(reading .. ' /' .. text .. ';@verb-' .. tag .. '/')
    for okuri in accepted
      const prepared = conversion.Prepare({[reading]: entry}, state.State.new(), reading, okuri)
      assert.equals(prepared.TextAt(0), text .. okuri)
    endfor
    for okuri in rejected
      assert.equals(conversion.Prepare({[reading]: entry}, state.State.new(), reading, okuri).candidates, [], tag .. ': ' .. okuri)
    endfor
  endfor
}

suite.kuru_one_source_supplies_ku_ko_and_ki_without_rewriting_it = (): void => {
  const entry = parser.ParseLine('く /来;説明 @verb-henkaku-k/句;@verb-5-k/区/')
  for [reading, okuri, expected] in [['く', 'る', '来る'], ['こ', 'よう', '来よう'],
      ['こ', 'ない', '来ない'], ['き', 'ます', '来ます'], ['き', 'た', '来た'], ['き', 'ちゃう', '来ちゃう']]
    const prepared = conversion.Prepare({'く': entry}, state.State.new(), reading, okuri)
    assert.equals(len(prepared.candidates), 1)
    assert.equals(prepared.TextAt(0), expected)
    assert.equals(prepared.PreferenceQuery(0).reading, 'く')
  endfor
  assert.equals(entry.candidates[0].text, '来')
  assert.equals(conversion.Prepare({'く': entry}, state.State.new(), 'こ').candidates, [])
  assert.equals(conversion.Prepare({'く': entry}, state.State.new(), 'き').candidates, [])
}

suite.kuru_indexed_sources_keep_dictionary_order_and_ordinary_duplicates = (): void => {
  const original = dict_index.SourceFromLines(['く /来;@verb-henkaku-k/'])
  const ordinary = dict_index.SourceFromLines(['こy /通常/来/'])
  for sources in [[original, ordinary], [ordinary, original]]
    const prepared = conversion.Prepare({}, state.State.new(), 'こ', 'よう', true, dict_index.Database.new(sources))
    assert.equals(mapnew(prepared.candidates, (_, candidate) => candidate.text),
      sources[0] is original ? ['来', '通常', '来'] : ['通常', '来', '来'])
  endfor
}

suite.kuru_learning_and_explicit_choices_follow_the_registered_reading = (): void => {
  const entries = {'く': parser.ParseLine('く /来;@verb-henkaku-k/來;@verb-henkaku-k/')}
  const preferences = state.State.new()
  const selected = conversion.Selection.new(conversion.Prepare(entries, preferences, 'こ', 'よう'), preferences)
  selected.Select(1)
  selected.Commit()
  const restored = state.State.new()
  restored.Restore(codec.Decode(codec.Encode(preferences.GetSnapshot())))
  assert.equals(conversion.Prepare(entries, restored, 'き', 'ます').TextAt(0), '來ます')
  const pinned = conversion.Selection.new(conversion.Prepare(entries, restored, 'き', 'ます'), restored)
  pinned.TogglePin()
  assert.equals(conversion.Selection.new(conversion.Prepare(entries, restored, 'く', 'る'), restored).GetInfo().tier, 'pinned')
  pinned.ToggleDemote()
  assert.equals(conversion.Prepare(entries, restored, 'こ', 'ない').TextAt(0), '来ない')
}

suite.kuru_user_registration_with_okuri_is_deleted_from_its_ko_variant = (): void => {
  const preferences = state.State.new()
  preferences.AddEntry(lookup.CreateQuery('く', 'る'), dictionary.Candidate.new('来', ['@verb-henkaku-k']))
  const compiled = scheme.Compile({}, {}, [scheme.SpecialDefinition.new(['x'], 'よう')])
  const ime = session.Session.new(compiled, '', {}, preferences, 'こ')
  assert.equals(ime.Feed('X')[-1].text, '来よう')
  assert.equals(ime.CanDeleteUserEntry(), true)
  ime.DeleteUserEntry()
  assert.equals(preferences.GetSnapshot().entries, {})
}

suite.kuru_latest_choice_still_wins_against_ordinary_candidates_in_each_variant = (): void => {
  const entries = {'く': parser.ParseLine('く /来;@verb-henkaku-k/'),
    'こy': parser.ParseLine('こy /通常/'), 'きm': parser.ParseLine('きm /通常/')}
  const preferences = state.State.new()
  preferences.Learn(lookup.CreateQuery('こ', 'よ'), '通常')
  preferences.Learn(lookup.CreateQuery('き', 'ま'), '通常')
  const selected = conversion.Selection.new(conversion.Prepare(entries, preferences, 'く', 'る'), preferences)
  selected.Commit()
  assert.equals(conversion.Prepare(entries, preferences, 'こ', 'よう').TextAt(0), '来よう')
  assert.equals(conversion.Prepare(entries, preferences, 'き', 'ます').TextAt(0), '来ます')
  const ordinary = conversion.Selection.new(conversion.Prepare(entries, preferences, 'こ', 'よう'), preferences)
  ordinary.Select(1)
  ordinary.Commit()
  assert.equals(conversion.Prepare(entries, preferences, 'こ', 'よう').TextAt(0), '通常よう')
  const again = conversion.Selection.new(conversion.Prepare(entries, preferences, 'く', 'る'), preferences)
  again.Commit()
  const restored = state.State.new()
  restored.Restore(codec.Decode(codec.Encode(preferences.GetSnapshot())))
  assert.equals(conversion.Prepare(entries, restored, 'こ', 'よう').TextAt(0), '来よう')
}



def RestoreKuruUserState(snapshot: state.Snapshot)
  runtime.Get().Restore(snapshot)
enddef

suite.kuru_real_input_commits_and_cancels_using_the_entered_reading = (): void => {
  const previous = bufnr('%')
  const snapshot = runtime.Get().GetSnapshot()
  defer RestoreKuruUserState(snapshot)
  const path = tempname()
  defer delete(path)
  writefile(['く /来;@verb-henkaku-k/'], path)
  enew
  const buffer = bufnr('%')
  setlocal buftype=nofile noswapfile
  try
    Caskk.RegisterInputScheme({name: 'kuru-test', consonants: {}, combinations: {},
      specials: {x: 'こ', y: 'よう', z: 'き', m: 'ます'}})
    Caskk.Config({dictionaries: [path], mode_popup: false, candidate_popup: false,
      mappings: {c: 'Commit', q: 'PreviousCandidate'}})
    Caskk.Enable('kuru-test')
    feedkeys("iXYc\<Esc>", 'xt')
    assert.equals(getline(1), '来よう')
    undo
    assert.equals(getline(1), 'こよう')
    undo
    assert.equals(getline(1), '')
    feedkeys("iZMc\<Esc>", 'xt')
    assert.equals(getline(1), '来ます')
    undo
    undo
    feedkeys("iXYqc\<Esc>", 'xt')
    assert.equals(getline(1), 'こよう')
  finally
    Caskk.Disable()
    Caskk.Config({})
    execute 'noautocmd keepalt hide buffer ' .. previous
    execute 'silent! bwipeout! ' .. buffer
  endtry
}
