vim9script

import autoload 'caskk.vim' as Caskk
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/user_state/codec.vim' as codec
import autoload 'caskk/user_state/store.vim' as store

final suite = themis#suite('interactive registration window')
const assert = themis#helper('assert')
var origin_window: number
var origin_buffer: number
var registration_buffer: number = 0
var registration_window: number = 0
var errors: list<string> = []
var initial_texts: list<string> = []
var initial_positions: list<number> = []
var initial_highlights: list<number> = []
var messages: list<string> = []
var intermediate_texts: list<string> = []
var origin_statusline: string = ''
var origin_winfixheight: bool = false
var baseline_statusline: string = ''
var baseline_winfixheight: bool = false

class Fixture
  const previous: number
  const buffer: number
  const directory: string
  const snapshot: user_state.Snapshot
  const existing_buffers: list<number>

  def new(this.previous, this.buffer, this.directory, this.snapshot, this.existing_buffers)
  enddef
endclass

def Handle(action: string)
  try
    if action ==# 'open'
      Caskk.OpenRegistration()
      registration_buffer = bufnr('%')
      registration_window = win_getid()
      initial_texts->add(getline(1))
      initial_positions->add(col('.'))
      initial_highlights->add(len(prop_list(1, {types: ['caskk_preedit']})))
      inoremap <buffer> <F4> <ScriptCmd>Handle('message')<CR>
      nnoremap <buffer> <F5> <ScriptCmd>Handle('close')<CR>
      inoremap <buffer> <F6> <ScriptCmd>Handle('wipe-origin')<CR>
      inoremap <buffer> <F7> <ScriptCmd>Handle('close-origin')<CR>
      inoremap <buffer> <F8> <ScriptCmd>Handle('disable-origin')<CR>
    elseif action ==# 'message'
      messages->add(&l:statusline)
      intermediate_texts->add(getline(1))
    elseif action ==# 'close'
      close!
    elseif action ==# 'wipe-origin'
      execute 'bwipeout! ' .. origin_buffer
    elseif action ==# 'close-origin'
      win_execute(origin_window, 'close!')
    elseif action ==# 'disable-origin'
      win_gotoid(origin_window)
      Caskk.Disable()
    endif
  catch
    errors->add(v:exception)
  endtry
enddef

defcompile Handle

def Setup(prefill: bool = true): Fixture
  const existing_buffers = mapnew(getbufinfo(), (_, info) => info.bufnr)
  const previous = bufnr('%')
  origin_buffer = bufadd('')
  bufload(origin_buffer)
  execute 'noautocmd keepalt hide buffer ' .. origin_buffer
  origin_window = win_getid()
  baseline_statusline = &l:statusline
  baseline_winfixheight = &l:winfixheight
  setlocal statusline=元の表示 nowinfixheight
  origin_statusline = &l:statusline
  origin_winfixheight = &l:winfixheight
  setlocal buftype=nofile noswapfile
  setline(1, '前後')
  cursor(1, 1)
  registration_buffer = 0
  registration_window = 0
  errors = []
  initial_texts = []
  initial_positions = []
  initial_highlights = []
  messages = []
  intermediate_texts = []
  const directory = tempname()
  mkdir(directory)
  const snapshot = user_runtime.Get().GetSnapshot()
  user_runtime.Get().Restore(user_state.State.new().GetSnapshot())
  Caskk.Config({registration_auto: false, registration_prefill: prefill,
    state_path: directory .. '/state.jsonl',
    mappings: {s: 'Convert', n: 'NextCandidate'}})
  Caskk.RegisterInputScheme({name: 'registration-window', consonants: {k: 'k'}, combinations: {a: 'a'},
    specials: {d: '漢字', zx: 'い*くらい'}})
  Caskk.Enable('registration-window')
  inoremap <buffer> <F3> <ScriptCmd>Handle('open')<CR>
  return Fixture.new(previous, origin_buffer, directory, snapshot, existing_buffers)
enddef

def Cleanup(fixture: Fixture)
  try
    if win_id2win(origin_window) > 0
      win_gotoid(origin_window)
    endif
    if bufnr('%') == fixture.buffer
      Caskk.Disable()
    endif
    feedkeys('', 'x')
  finally
    if registration_window > 0 && win_id2win(registration_window) > 0 && winnr('$') > 1
      win_execute(registration_window, 'close!')
    endif
    execute 'noautocmd keepalt hide buffer ' .. fixture.previous
    &l:statusline = baseline_statusline
    &l:winfixheight = baseline_winfixheight
    if bufexists(fixture.buffer)
      execute 'silent! bwipeout! ' .. fixture.buffer
    endif
    if registration_buffer > 0 && bufexists(registration_buffer)
      execute 'silent! bwipeout! ' .. registration_buffer
    endif
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

suite.prefilled_registration_uses_ime_input_and_preserves_persistence_and_undo = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const windows = winnr('$')
  feedkeys("aKas\<F3>\<BS>d\<CR>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(initial_texts, ['か'])
  assert.equals(initial_positions, [4])
  assert.equals(initial_highlights, [1])
  assert.equals(win_getid(), origin_window)
  assert.equals(getline(1), '前漢字か後')
  assert.equals(winnr('$'), windows)
  assert.equals(&l:bufhidden, '')
  assert.equals(bufexists(registration_buffer), 0)
  Caskk.SaveState()
  const stored = store.Load(fixture.directory .. '/state.jsonl')
  assert.equals(stored.entries[json_encode(['か', ''])][0].text, '漢字')
  for expected in ['前漢字後', '前か後', '前後']
    normal! u
    assert.equals(getline(1), expected)
  endfor
}

suite.prefill_can_be_disabled_without_disabling_the_input_method = (): void => {
  const fixture = Setup(false)
  defer Cleanup(fixture)
  feedkeys("aKas\<F3>d\<CR>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(initial_texts, [''])
  assert.equals(initial_highlights, [0])
  assert.equals(getline(1), '前漢字後')
}

suite.escape_cancels_registration_and_keeps_the_original_reading_editable = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys("aKas\<F3>\<BS>d\<Esc>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前かか後')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
  assert.equals(bufexists(registration_buffer), 0)
}

suite.okuri_registration_prefills_only_reading_and_appends_full_suffix_once = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys("aZX\<F3>\<BS>d\<CR>ZX\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(initial_texts, ['い'])
  assert.equals(getline(1), '前漢字くらい漢字くらい後')
  const entries = user_runtime.Get().GetSnapshot().entries
  assert.equals(entries[json_encode(['い', 'く'])][0].text, '漢字')
}

suite.closing_registration_window_cancels_and_resumes_the_original_input = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys("aKas\<F3>\<C-c>\<F5>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前かか後')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
  assert.equals(bufexists(registration_buffer), 0)
}

suite.wiping_origin_buffer_removes_orphaned_registration_window_without_registering = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys("aKas\<F3>\<F6>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(bufexists(fixture.buffer), 0)
  assert.equals(bufexists(registration_buffer), 0)
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.closing_origin_window_keeps_plain_reading_and_removes_registration_ui = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys("aKas\<F3>\<F7>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getbufline(fixture.buffer, 1), ['前か後'])
  assert.equals(bufexists(registration_buffer), 0)
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
  assert.equals(prop_list(1, {bufnr: fixture.buffer, types: ['caskk_preedit']}), [])
  assert.equals(&l:statusline, origin_statusline)
  assert.equals(&l:winfixheight, origin_winfixheight)
  assert.equals(getbufvar(fixture.buffer, '&bufhidden'), '')
}

suite.empty_candidate_keeps_registration_open_for_retry = (): void => {
  const fixture = Setup(false)
  defer Cleanup(fixture)
  feedkeys("aKas\<F3>\<CR>\<F4>d\<CR>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(len(messages), 1)
  assert.equals(stridx(messages[0], '登録語を入力してください') >= 0, true)
  assert.equals(getline(1), '前漢字後')
}

suite.opening_without_registration_request_does_not_create_a_window = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const windows = winnr('$')
  feedkeys("aKa\<F3>ka\<Esc>", 'xt')
  assert.equals(errors, ['caskk: no current dictionary registration request'])
  assert.equals(winnr('$'), windows)
  assert.equals(getline(1), '前かか後')
  assert.equals(registration_buffer, 0)
}

suite.registration_can_be_completed_from_normal_mode = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  feedkeys("aKas\<F3>\<BS>d\<C-c>\<CR>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前漢字か後')
  assert.equals(bufexists(registration_buffer), 0)
}

suite.invalid_prefill_setting_keeps_previous_ui_configuration = (): void => {
  const fixture = Setup(false)
  defer Cleanup(fixture)
  var caught = ''
  try
    Caskk.Config({registration_prefill: 1})
  catch
    caught = v:exception
  endtry
  assert.equals(caught, 'caskk: invalid configuration: registration_prefill must be a bool')
  feedkeys("aKas\<F3>d\<CR>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(initial_texts, [''])
  assert.equals(getline(1), '前漢字後')
}

suite.disabling_origin_closes_registration_without_applying_a_late_result = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys("aKas\<F3>\<F8>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前かka後')
  assert.equals(Caskk.IsEnabled(), false)
  assert.equals(bufexists(registration_buffer), 0)
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.cancelling_does_not_commit_an_unconfirmed_candidate_inside_registration = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const path = fixture.directory .. '/system'
  writefile(['か /蚊/科/'], path)
  Caskk.Disable()
  Caskk.Config({registration_auto: false, dictionaries: [path], mappings: {s: 'Convert'}})
  Caskk.Enable('registration-window')
  const before = codec.Encode(user_runtime.Get().GetSnapshot())
  feedkeys("aZX\<F3>\<BS>Kas\<F4>\<Esc>ka\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(intermediate_texts, ['蚊'])
  assert.equals(getline(1), '前いくらいか後')
  assert.equals(codec.Encode(user_runtime.Get().GetSnapshot()), before)
}

suite.completing_with_an_inner_conversion_learns_and_registers_the_confirmed_body = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const path = fixture.directory .. '/system'
  writefile(['か /蚊/科/'], path)
  Caskk.Disable()
  Caskk.Config({registration_auto: false, dictionaries: [path], mappings: {s: 'Convert'}})
  Caskk.Enable('registration-window')
  feedkeys("aZX\<F3>\<BS>Kas\<CR>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前蚊くらい後')
  const snapshot = user_runtime.Get().GetSnapshot()
  assert.equals(snapshot.entries[json_encode(['い', 'く'])][0].text, '蚊')
  assert.equals(snapshot.mru[json_encode(['か', ''])], ['蚊'])
  assert.equals(snapshot.mru[json_encode(['い', 'く'])], ['蚊'])
}

suite.configured_open_action_starts_the_window_and_honors_prefill_setting = (): void => {
  const fixture = Setup()
  defer Cleanup(fixture)
  const windows = winnr('$')
  Caskk.Disable()
  Caskk.Config({registration_auto: false, registration_prefill: false,
    mappings: {s: 'Convert', '<F3>': 'OpenRegistration'}})
  Caskk.Enable('registration-window')
  feedkeys("aKas\<F3>d\<CR>\<Esc>", 'xt')
  assert.equals(errors, [])
  assert.equals(getline(1), '前漢字後')
  assert.equals(winnr('$'), windows)
  for info in getbufinfo()
    assert.equals(info.bufnr == fixture.buffer || index(fixture.existing_buffers, info.bufnr) >= 0, true)
  endfor
}
