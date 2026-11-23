vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/scheme.vim' as scheme
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/user_state/codec.vim' as codec

final suite = themis#suite('candidate information popup')
const assert = themis#helper('assert')

class Observation
  const popups: list<number>
  const buffers: list<number>
  const lines: list<string>
  const firstline: number
  const height: number
  const buffer: number
  const window: number
  const position: dict<number>
  const cursor: list<number>
  const preview: string

  def new(this.popups, this.buffers, this.lines, this.firstline, this.height, this.buffer, this.window, this.cursor, this.position, this.preview)
  enddef
endclass

var observations: list<Observation> = []
var selected_rows: list<number> = []
var preference_revisions: list<number> = []
var registration_readings: list<string> = []
var selection_groups: list<string> = []
var ignored_popups: list<number> = []
var origin_buffer: number = 0
const CAPTURE = "\<Cmd>call CaskkTestCandidatePopupCapture()\<CR>"
const WIPE = "\<Cmd>call CaskkTestCandidatePopupWipe()\<CR>"

def g:CaskkTestCandidatePopupCapture()
  preference_revisions->add(user_runtime.Get().Revision())
  const request = Caskk.GetRegistrationRequest()
  registration_readings->add(request is null_object ? '' : request.reading)
  const popups = filter(popup_list(), (_, id) => index(ignored_popups, id) < 0)
  const buffers = mapnew(popups, (_, id) => winbufnr(id))
  const lines = len(buffers) == 1 ? getbufline(buffers[0], 1, '$') : []
  const position = len(popups) == 1 ? popup_getpos(popups[0]) : {}
  var selected_row = 0
  if len(buffers) == 1
    for row in range(1, len(lines))
      if !empty(filter(prop_list(row, {bufnr: buffers[0]}), (_, property) => property.type ==# 'caskk_candidate_selected'))
        selected_row = row
      endif
    endfor
  endif
  selected_rows->add(selected_row)
  selection_groups->add(len(buffers) == 1
    ? get(prop_type_get('caskk_candidate_selected', {bufnr: buffers[0]}), 'highlight', '') : '')
  observations->add(Observation.new(popups, buffers, lines, get(position, 'firstline', 0),
    get(position, 'height', 0), bufnr('%'), win_getid(), [line('.'), col('.')], position, getline(1)))
enddef

def g:CaskkTestCandidatePopupWipe()
  execute 'bwipeout! ' .. origin_buffer
enddef

class Fixture
  const previous: number
  const buffer: number
  const window: number
  const directory: string
  const snapshot: user_state.Snapshot
  const existing_buffers: list<number>
  const existing_popups: list<number>

  def new(this.previous, this.buffer, this.window, this.directory, this.snapshot,
      this.existing_buffers, this.existing_popups)
  enddef
endclass

def Setup(candidate_popup: bool = true, extra_mappings: dict<string> = {}, candidate_count: number = 2,
    keep_preedit_on_backspace: bool = true, options: dict<any> = {candidate_select_keys: []},
    annotation: string = '昆虫'): Fixture
  const previous = bufnr('%')
  const existing_buffers = mapnew(getbufinfo(), (_, info) => info.bufnr)
  const existing_popups = popup_list()
  ignored_popups = copy(existing_popups)
  const number = bufadd('')
  bufload(number)
  execute 'noautocmd keepalt hide buffer ' .. number
  const window = win_getid()
  origin_buffer = number
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  const directory = tempname()
  mkdir(directory)
  var dictionary_line = 'か /蚊;' .. annotation .. '/科;学科'
  for index in range(3, candidate_count)
    dictionary_line ..= '/候補' .. index
  endfor
  writefile([dictionary_line .. '/'], directory .. '/system')
  const snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  observations = []
  selected_rows = []
  registration_readings = []
  preference_revisions = []
  selection_groups = []
  Caskk.RegisterInputScheme({name: 'candidate-popup', consonants: {k: 'k'},
    combinations: {a: 'a'}, specials: {d: '漢字', zx: 'い*くらい'}})
  var mappings = {s: 'Convert', n: 'NextCandidate', p: 'PreviousCandidate', c: 'Commit'}
  extend(mappings, extra_mappings)
  Caskk.Config(extend({keep_preedit_on_backspace: keep_preedit_on_backspace, candidate_popup: candidate_popup, mode_popup: false, dictionaries: [directory .. '/system'],
    mappings: mappings}, options))
  Caskk.Enable('candidate-popup')
  return Fixture.new(previous, number, window, directory, snapshot, existing_buffers, existing_popups)
enddef

def Cleanup(fixture: Fixture)
  try
    win_gotoid(fixture.window)
    Caskk.Disable()
    feedkeys('', 'x')
  finally
    for id in popup_list()
      if index(fixture.existing_popups, id) < 0
        popup_close(id)
      endif
    endfor
    execute 'noautocmd keepalt hide buffer ' .. fixture.previous
    for info in getbufinfo()
      if index(fixture.existing_buffers, info.bufnr) < 0
        execute 'silent! bwipeout! ' .. info.bufnr
      endif
    endfor
    Caskk.Config({})
    user_runtime.Get().Restore(fixture.snapshot)
    delete(fixture.directory, 'rf')
  endtry
enddef

suite.navigation_updates_the_ranked_candidate_list_without_moving_the_input_cursor = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. 'n' .. CAPTURE .. 'p' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['蚊 — 昆虫', '科 — 学科'])
  assert.equals(observations[1].lines, ['蚊 — 昆虫', '科 — 学科'])
  assert.equals(observations[2].lines, ['蚊 — 昆虫', '科 — 学科'])
  for observed in observations
    assert.equals(len(observed.popups), 1)
    assert.equals(observed.buffer, fixture.buffer)
    assert.equals(observed.window, fixture.window)
    assert.equals(observed.cursor, [1, 7])
  endfor
  assert.equals(getline(1), '前蚊後')
  assert.equals(selected_rows, [1, 2, 1])
  assert.equals(selection_groups, ['PmenuSel', 'PmenuSel', 'PmenuSel'])
}

suite.unlabelled_candidates_scroll_from_the_third_row = (): void => {
  const fixture = Setup(true, {}, 4)
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. repeat('n' .. CAPTURE, 3)
    .. repeat('p' .. CAPTURE, 3) .. "c\<Esc>", 'xt')
  assert.equals(mapnew(observations, (_, observed) => observed.firstline), [1, 1, 1, 2, 1, 1, 1])
  assert.equals(mapnew(selected_rows, (i, row) => row - observations[i].firstline + 1),
    [1, 2, 3, 3, 3, 2, 1])
  assert.equals(mapnew(observations, (_, observed) => observed.height), repeat([4], 7))
}

suite.wrapped_annotation_keeps_the_selected_candidate_visible = (): void => {
  const fixture = Setup(true, {}, 4, true, {candidate_select_keys: []}, repeat('昆虫', &lines * 16))
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. repeat('n' .. CAPTURE, 2)
    .. repeat('p' .. CAPTURE, 2) .. "c\<Esc>", 'xt')
  assert.equals(selected_rows, [1, 2, 3, 2, 1])
  assert.equals(mapnew(observations, (_, observed) => observed.firstline), [1, 2, 2, 2, 1])
  assert.equals(mapnew(observations, (_, observed) => observed.height), repeat([observations[0].height], 5))
}

suite.selected_candidate_stays_inside_a_scrolled_popup_with_many_candidates = (): void => {
  const fixture = Setup(true, {}, 40)
  defer Cleanup(fixture)
  feedkeys('aKas' .. repeat('n', 25) .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(len(observations), 1)
  const selected = selected_rows[0] - 1
  assert.equals(selected, 25)
  assert.equals(observations[0].firstline <= selected + 1, true)
  assert.equals(selected + 1 < observations[0].firstline + observations[0].height, true)
}

suite.mapping_removes_the_selected_user_entry_and_refreshes_candidate_selection = (): void => {
  const fixture = Setup(true, {x: 'DeleteUserEntry'})
  defer Cleanup(fixture)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  feedkeys('aKasnnx' .. CAPTURE .. 'y' .. CAPTURE .. "c\<Esc>", 'xt')
  const identity = json_encode(['か', ''])
  assert.equals(observations[0].lines[-1], 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消')
  assert.equals(has_key(user_runtime.Get().GetSnapshot().entries, identity), false)
  assert.equals(user_runtime.Get().GetSnapshot().entries, {})
  assert.equals(observations[1].lines,
    ['蚊 — 昆虫', '科 — 学科'])
  assert.equals(getline(1), '前科後')
}

suite.cancelling_user_entry_deletion_keeps_the_entry_and_selected_candidate = (): void => {
  const fixture = Setup(true, {x: 'DeleteUserEntry'})
  defer Cleanup(fixture)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  const identity = json_encode(['か', ''])
  feedkeys('aKasnnx' .. CAPTURE .. 'n' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(has_key(user_runtime.Get().GetSnapshot().entries, identity), true)
  assert.equals(user_runtime.Get().GetSnapshot().entries[identity][0].text, '登録のみ')
  assert.equals(observations[0].lines[-1], 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消')
  assert.equals(observations[1].lines[-1], '登録のみ')
  assert.equals(getline(1), '前登録のみ後')
}

suite.esc_cancels_user_entry_deletion_without_leaving_the_candidate = (): void => {
  const fixture = Setup(true, {x: 'DeleteUserEntry'})
  defer Cleanup(fixture)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  const identity = json_encode(['か', ''])
  feedkeys('aKasnnx' .. CAPTURE .. "\<Esc>" .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines[-1], 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消')
  assert.equals(observations[1].lines[-1], '登録のみ')
  assert.equals(has_key(user_runtime.Get().GetSnapshot().entries, identity), true)
  assert.equals(getline(1), '前登録のみ後')
}

suite.mappings_toggle_pin_and_demote_for_the_selected_candidate = (): void => {
  const fixture = Setup(true, {v: 'TogglePin', b: 'ToggleDemote'})
  defer Cleanup(fixture)
  feedkeys("aKasv" .. CAPTURE .. "b" .. CAPTURE .. "b" .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['★ 蚊 — 昆虫', '科 — 学科'])
  assert.equals(observations[1].lines, ['↓ 蚊 — 昆虫', '科 — 学科'])
  assert.equals(observations[2].lines, ['蚊 — 昆虫', '科 — 学科'])
  const snapshot = user_runtime.Get().GetSnapshot()
  assert.equals(snapshot.pinned, {})
  assert.equals(snapshot.demoted, {})
}

suite.commit_closes_owned_popup_and_buffer_without_closing_an_unrelated_popup = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const foreign = popup_create('別の表示', {line: 1, col: 1})
  ignored_popups->add(foreign)
  feedkeys('aKas' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(len(observations[0].popups), 1)
  assert.equals(empty(popup_getpos(foreign)), false)
  assert.equals(empty(popup_getpos(observations[0].popups[0])), true)
  assert.equals(bufexists(observations[0].buffers[0]), 0)
  normal! u
  assert.equals(getline(1), '前か後')
  normal! u
  assert.equals(getline(1), '前後')
}

suite.returning_from_first_candidate_to_reading_closes_the_popup_without_learning = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys('aKas' .. CAPTURE .. 'p' .. CAPTURE .. "\<Esc>", 'xt')
  assert.equals(len(observations[0].popups), 1)
  assert.equals(observations[1].popups, [])
  assert.equals(getline(1), '前か後')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.exhaustion_closes_candidate_popup_before_opening_registration = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. 'nn' .. CAPTURE .. "\<Esc>\<Esc>", 'xt')
  assert.equals(len(observations[0].popups), 1)
  assert.equals(observations[1].popups, [])
  assert.equals(observations[1].buffer != fixture.buffer, true)
  assert.equals(bufexists(observations[0].buffers[0]), 0)
  assert.equals(getline(1), '前科後')
}

suite.registration_escape_restores_the_last_page_and_its_label = (): void => {
  for inline in [false, true]
    const fixture = Setup(true, {}, 3, true,
      {candidate_select_keys: ['1', '2'], registration_inline: inline, registration_prefill: false})
    try
      feedkeys('aKass' .. CAPTURE .. 's' .. "\<Esc>" .. CAPTURE .. 'p' .. CAPTURE
        .. "s1\<Esc>", 'xt')
      assert.equals(observations[0].lines, ['1 候補3'])
      assert.equals(observations[1].lines, observations[0].lines)
      assert.equals(observations[1].preview, '前候補3後')
      assert.equals(observations[1].buffer, fixture.buffer)
      assert.equals(registration_readings[1], '')
      assert.equals(preference_revisions[1], preference_revisions[0])
      assert.equals(observations[2].lines, ['1 蚊 — 昆虫', '2 科 — 学科'])
      assert.equals(getline(1), '前候補3後')
      assert.equals(user_runtime.Get().GetSnapshot().entries, {})
      normal! u
      assert.equals(getline(1), '前か後')
      normal! u
      assert.equals(getline(1), '前後')
    finally
      Cleanup(fixture)
    endtry
  endfor
}

suite.closing_the_split_restores_the_unlabelled_candidate = (): void => {
  const fixture = Setup(true, {}, 2, true, {candidate_select_keys: [], registration_prefill: false})
  defer Cleanup(fixture)
  feedkeys('aKasnnKas' .. "\<Cmd>close\<CR>" .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].buffer, fixture.buffer)
  assert.equals(selected_rows, [2])
  assert.equals(getline(1), '前科後')
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['か', ''])], ['科'])
}

suite.public_cancel_restores_the_candidate_without_opening_registration = (): void => {
  const fixture = Setup(true, {}, 2, true, {candidate_select_keys: [], registration_auto: false})
  defer Cleanup(fixture)
  feedkeys('aKasnn' .. "\<Cmd>call caskk#CancelRegistration()\<CR>" .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(registration_readings, [''])
  assert.equals(selected_rows, [2])
  assert.equals(getline(1), '前科後')
}

suite.inline_escape_commits_the_draft_candidate_before_restoring_the_source_page = (): void => {
  const fixture = Setup(true, {}, 3, true,
    {candidate_select_keys: ['1', '2'], registration_inline: true, registration_prefill: false})
  defer Cleanup(fixture)
  feedkeys('aKasssKassp' .. "\<Esc>" .. CAPTURE .. "\<Esc>" .. CAPTURE .. "1\<Esc>", 'xt')
  assert.equals(registration_readings, ['か', ''])
  assert.equals(observations[1].lines, ['1 候補3'])
  assert.equals(getline(1), '前候補3後')
  assert.equals(user_runtime.Get().GetSnapshot().entries, {})
}

suite.cancelling_registration_discards_the_inner_candidate_popup_without_learning = (): void => {
  const fixture = Setup(true, {}, 2, false)
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys('aZX' .. "\<BS>Kas" .. CAPTURE .. "\<Esc>ka\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['蚊 — 昆虫', '科 — 学科'])
  assert.equals(empty(popup_getpos(observations[0].popups[0])), true)
  assert.equals(bufexists(observations[0].buffers[0]), 0)
  assert.equals(getline(1), '前いくらいか後')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.wiping_the_input_buffer_closes_the_popup_after_normal_session_commit = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. WIPE .. "\<Esc>", 'xt')
  assert.equals(len(observations[0].popups), 1)
  assert.equals(empty(popup_getpos(observations[0].popups[0])), true)
  assert.equals(bufexists(observations[0].buffers[0]), 0)
  assert.equals(bufexists(fixture.buffer), 0)
  assert.equals(user_runtime.Get().GetSnapshot().mru[json_encode(['か', ''])], ['蚊'])
  assert.equals(user_runtime.Get().GetSnapshot().entries, {})
}

suite.disabling_popup_and_rejecting_invalid_setting_does_not_disable_conversion = (): void => {
  const fixture = Setup(false)
  defer Cleanup(fixture)
  var caught = ''
  try
    Caskk.Config({candidate_popup: 1})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: invalid configuration: candidate_popup must be a bool')
  feedkeys('aKas' .. CAPTURE .. 'n' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].popups, [])
  assert.equals(observations[1].popups, [])
  assert.equals(getline(1), '前科後')
}

suite.candidate_popup_keeps_its_position_and_height_near_the_end = (): void => {
  const fixture = Setup(true, {}, 40)
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. repeat('n', 36) .. CAPTURE .. 'nn' .. CAPTURE .. "c\<Esc>", 'xt')
  const initial = observations[0].position
  for observed in observations[1 : ]
    assert.equals([observed.position.line, observed.position.col, observed.height],
      [initial.line, initial.col, observations[0].height])
  endfor
}

suite.short_labelled_list_touches_the_conversion_row_near_the_bottom = (): void => {
  const fixture = Setup(true, {}, 2, true, {candidate_select_keys: ['1', '2', '3']})
  defer Cleanup(fixture)
  botright split
  defer execute('close')
  resize 1
  redraw!
  const row = screenpos(win_getid(), line('.'), col('.')).row
  feedkeys('aKas' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['1 蚊 — 昆虫', '2 科 — 学科'])
  assert.equals(observations[0].position.line + observations[0].height, row)
}

suite.short_final_page_stays_above_the_conversion_row = (): void => {
  const fixture = Setup(true, {}, 5, true, {candidate_select_keys: ['1', '2', '3', '4']})
  defer Cleanup(fixture)
  botright split
  defer execute('close')
  resize 3
  redraw!
  const row = screenpos(win_getid(), line('.'), col('.')).row
  feedkeys('aKas' .. CAPTURE .. 'n' .. CAPTURE .. 'p' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(mapnew(observations, (_, observed) => observed.height), [4, 1, 4])
  for observed in observations
    assert.equals(observed.position.line + observed.height, row)
  endfor
}

suite.deletion_confirmation_is_fully_visible_in_a_small_terminal = (): void => {
  const script = tempname() .. '.vim'
  const report = tempname()
  defer delete(script)
  defer delete(report)
  writefile([
    'vim9script',
    'set rtp^=' .. escape(getcwd(), ' ,'),
    'const inline = readfile(' .. string(report) .. ')[0] ==# "inline"',
    "import autoload 'caskk.vim' as C",
    "import autoload 'caskk/user_state/runtime.vim' as runtime",
    "import autoload 'caskk/dictionary/lookup.vim' as lookup",
    "import 'caskk/dictionary.vim' as dictionary",
    "C.RegisterInputScheme({name: 'small-confirmation', consonants: {k: 'k'}, combinations: {a: 'a', i: 'i'}})",
    "C.Config({candidate_select_keys: [], mode_popup: false, registration_auto: false, registration_inline: inline, registration_prefill: false, mappings: {s: 'Convert', x: 'DeleteUserEntry', q: 'OpenRegistration'}})",
    "runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('蚊', ['昆虫']))",
    "C.Enable('small-confirmation')",
    'def Capture(timer: number)',
    "  writefile([string(runtime.Get().HasEntryForLookup(lookup.CreateQuery('か', ''), '蚊'))], " .. string(report) .. ')',
    'enddef',
    'timer_start(10, Capture, {repeat: -1})',
    'writefile(["ready"], ' .. string(report) .. ')',
  ], script)
  for dimensions in [[8, 24, false], [6, 36, false], [8, 24, true], [6, 36, true]]
    writefile([dimensions[2] ? 'inline' : 'normal'], report)
    const terminal = term_start([v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-N', '-S', script],
      {hidden: true, term_rows: dimensions[0], term_cols: dimensions[1]})
    try
      for _ in range(100)
        term_wait(terminal, 10)
        if readfile(report) == ['ready'] || readfile(report) == ['true']
          break
        endif
      endfor
      term_sendkeys(terminal, dimensions[2] ? 'iKisqKasx' : 'iKasx')
      term_wait(terminal, 100)
      const screen = join(mapnew(range(1, dimensions[0]), (_, row) => term_getline(terminal, row)), '')
      # Ignore background cells and Vim's filler before a wrapped wide character.
      const compact = substitute(screen, '[[:space:]~>]', '', 'g')
      assert.equals(stridx(compact, 'ユーザー辞書から削除しますか？y:削除n/Esc:取消') >= 0, true, screen)
      term_sendkeys(terminal, 'n')
      term_wait(terminal, 100)
      assert.equals(readfile(report), ['true'])
      const restored = join(mapnew(range(1, dimensions[0]), (_, row) => term_getline(terminal, row)), '')
      assert.equals(stridx(restored, dimensions[2] ? '辞書登録' : '蚊 — 昆虫') >= 0, true, restored)
      term_sendkeys(terminal, 'xy')
      term_wait(terminal, 100)
      assert.equals(readfile(report), ['false'])
    finally
      job_stop(term_getjob(terminal), 'kill')
      execute 'silent! bwipeout! ' .. terminal
    endtry
  endfor
}

suite.explicit_backspace_delete_mapping_keeps_its_confirmation_behavior = (): void => {
  const fixture = Setup(true, {"\<BS>": 'DeleteUserEntry'})
  defer Cleanup(fixture)
  user_runtime.Get().AddEntry(lookup.CreateQuery('か', ''), dictionary.Candidate.new('登録のみ', []))
  feedkeys('aKasnn' .. "\<BS>" .. CAPTURE .. 'y' .. CAPTURE .. "c\<Esc>", 'xt')
  assert.equals(observations[0].lines[-1], 'ユーザー辞書から削除しますか？ y:削除 n/Esc:取消')
  assert.equals(user_runtime.Get().HasEntryForLookup(lookup.CreateQuery('か', ''), '登録のみ'), false)
  assert.equals(observations[1].lines, ['蚊 — 昆虫', '科 — 学科'])
}

suite.unavailable_backspace_actions_cancel_conversion_without_learning = (): void => {
  for action in ['DeleteUserEntry', 'KatakanaMode', 'OpenRegistration', 'ShowCompletion', 'CancelCompletion']
    const fixture = Setup(true, {"\<BS>": action})
    try
      feedkeys('aKas' .. "\<BS>" .. CAPTURE .. "\<Esc>", 'xt')
      assert.equals(getline(1), '前後', action)
      assert.equals(observations[0].popups, [], action)
      assert.equals(user_runtime.Get().GetSnapshot().mru, {}, action)
    finally
      Cleanup(fixture)
    endtry
  endfor
}

suite.numeric_labels_commit_and_digits_remain_literal_afterward = (): void => {
  const fixture = Setup(true, {}, 2, true, {candidate_select_keys: ['1', '2', '3']})
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. "23\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['1 蚊 — 昆虫', '2 科 — 学科'])
  assert.equals(getline(1), '前科3後')
}

suite.four_labels_limit_pages_and_are_reused_in_order = (): void => {
  const fixture = Setup(true, {}, 5, true, {candidate_select_keys: ['4', '2', '3', '1']})
  defer Cleanup(fixture)
  feedkeys('aKas' .. CAPTURE .. 'n' .. CAPTURE .. 'p' .. CAPTURE .. 'n2' .. CAPTURE .. "4\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['4 蚊 — 昆虫', '2 科 — 学科', '3 候補3', '1 候補4'])
  assert.equals(observations[1].lines, ['4 候補5'])
  assert.equals(observations[2].lines, observations[0].lines)
  assert.equals(observations[3].lines, observations[1].lines)
  assert.equals(getline(1), '前候補5後')
}

suite.removed_candidate_page_size_is_an_unknown_option = (): void => {
  var error = ''
  try
    Caskk.Config({candidate_page_size: 4})
  catch
    error = v:exception
  endtry
  assert.equals(error, 'caskk: invalid configuration: unknown section: candidate_page_size')
}

suite.custom_pages_keep_labels_stable_when_editing_rank = (): void => {
  const fixture = Setup(true, {t: 'TogglePin', d: 'ToggleDemote', x: 'Commit'}, 3, true,
    {candidate_select_keys: ['x', 'y']})
  defer Cleanup(fixture)
  feedkeys('aKann' .. CAPTURE .. 'ypt' .. CAPTURE .. "y" .. CAPTURE .. "d\<Esc>" .. CAPTURE .. "xc\<Esc>", 'xt')
  assert.equals(observations[0].lines, ['x 候補3'])
  assert.equals(observations[1].lines[-1], '固定する候補のラベルを入力（Escで取消）')
  assert.equals(observations[2].lines, ['x 蚊 — 昆虫', 'y ★ 科 — 学科'])
  assert.equals(observations[3].lines, observations[2].lines)
  assert.equals(selected_rows[2], 0)
  assert.equals(getline(1), '前蚊c後')
  feedkeys("AKasx\<Esc>", 'xt')
  assert.equals(getline(1), '前蚊c後科')
}

suite.invalid_candidate_label_settings_are_rejected = (): void => {
  for options in [{candidate_select_keys: ['x', 'x']}, {candidate_select_keys: ['xy']},
      {candidate_select_keys: ["\<Tab>"]}]
    var error = ''
    try
      Caskk.Config(options)
    catch
      error = v:exception
    endtry
    assert.match(error, 'invalid configuration: candidate_')
  endfor
}

suite.page_edges_restore_reading_and_request_registration = (): void => {
  const fixture = Setup(true, {}, 3, true, {candidate_select_keys: ['1', '2'], registration_auto: false})
  defer Cleanup(fixture)
  feedkeys('aKasp' .. CAPTURE .. 'sss' .. CAPTURE .. "\<Esc>", 'xt')
  assert.equals(observations[0].lines, [])
  assert.equals(observations[1].lines, [])
  assert.equals(registration_readings, ['', 'か'])
  assert.equals(getline(1), '前か後')
}

suite.demotion_affects_the_next_conversion_and_navigation_dismisses_the_prompt = (): void => {
  const fixture = Setup(true, {t: 'TogglePin', d: 'ToggleDemote'}, 3, true, {candidate_select_keys: ['1', '2', '3']})
  defer Cleanup(fixture)
  feedkeys('aKasd' .. CAPTURE .. '2' .. CAPTURE .. 'tc' .. CAPTURE .. "\<Esc>AKas" .. CAPTURE .. "1\<Esc>", 'xt')
  assert.equals(observations[0].lines[-1], '降格する候補のラベルを入力（Escで取消）')
  assert.equals(observations[1].lines, ['1 蚊 — 昆虫', '2 ↓ 科 — 学科', '3 候補3'])
  assert.equals(observations[2].lines, [])
  assert.equals(selected_rows[1 : 2], [0, 0])
  assert.equals(observations[3].lines, ['1 蚊 — 昆虫', '2 候補3', '3 ↓ 科 — 学科'])
}

suite.custom_multibyte_label_temporarily_overrides_a_user_mapping = (): void => {
  const fixture = Setup(true, {}, 2, true, {candidate_select_keys: ['x', 'é']})
  defer Cleanup(fixture)
  inoremap <buffer> é literal
  feedkeys("aKaséé\<Esc>", 'xt')
  assert.equals(getline(1), '前科literal後')
  assert.equals(maparg('é', 'i'), 'literal')
}

suite.hidden_popup_leaves_default_labels_as_ordinary_input = (): void => {
  const fixture = Setup(false, {}, 2, true, {})
  defer Cleanup(fixture)
  feedkeys("aKas2\<Esc>", 'xt')
  assert.equals(getline(1), '前蚊2後')
}

suite.labels_match_the_visible_rows_in_a_small_terminal = (): void => {
  const script = tempname()
  const report = tempname()
  const dictionary_path = tempname()
  defer delete(script)
  defer delete(report)
  defer delete(dictionary_path)
  writefile(['か /一/二/三/四/五/六/七/八/'], dictionary_path)
  writefile([
    'vim9script',
    'set rtp^=' .. escape(getcwd(), ' ,'),
    "import autoload 'caskk.vim' as C",
    "C.RegisterInputScheme({name: 'small-labels', consonants: {k: 'k'}, combinations: {a: 'a'}})",
    "C.Config({mode_popup: false, dictionaries: [" .. string(dictionary_path) .. "], mappings: {s: 'Convert'}, candidate_select_keys: ['1', '2', '3', '4', '5', '6', '7', '8']})",
    "C.Enable('small-labels')",
    'def Capture(timer: number)',
    '  writefile([getline(1)], ' .. string(report) .. ')',
    'enddef',
    'timer_start(10, Capture, {repeat: -1})',
  ], script)
  const terminal = term_start([v:progpath, '-Nu', 'NONE', '-i', 'NONE', '-n', '-N', '-S', script],
    {hidden: true, term_rows: 8, term_cols: 36})
  try
    for _ in range(100)
      term_wait(terminal, 10)
      if filereadable(report)
        break
      endif
    endfor
    term_sendkeys(terminal, 'iKas')
    term_wait(terminal, 100)
    const rows = mapnew(range(1, 8), (_, row) => term_getline(terminal, row))
    for label in ['1 一', '2 二', '3 三', '4 四', '5 五', '6 六']
      assert.match(join(rows, "\n"), label)
    endfor
    assert.equals(stridx(join(rows), '7 七'), -1)
    term_sendkeys(terminal, '6')
    term_wait(terminal, 100)
    assert.equals(readfile(report), ['六'])
  finally
    job_stop(term_getjob(terminal), 'kill')
    execute 'silent! bwipeout! ' .. terminal
  endtry
}
