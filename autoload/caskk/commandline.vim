vim9script

import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/session.vim' as session
import autoload 'caskk/config.vim' as configuration
import autoload 'caskk/user_state/runtime.vim' as user_runtime
import autoload 'caskk/input/mapping.vim' as mapping
import autoload 'caskk/input/keycode.vim' as keycode
import autoload 'caskk/input/mode.vim' as input_mode
import autoload 'caskk/presentation/mode_popup.vim' as mode_popup
import autoload 'caskk/presentation/candidate.vim' as candidate_popup

var depth = getcmdtype() == '' ? 0 : 1
var active = false
var compiled: scheme.CompiledScheme = null_object
var current: session.Session = null_object
var expected = ''
var position = 1
var start = 0
var finish = 0
var changing = false
var saved: dict<dict<any>> = {}
var installed: dict<dict<any>> = {}
const view = mode_popup.View.new()
const candidates = candidate_popup.View.new()

export def IsTarget(): bool
  return index([':', '/', '?'], getcmdtype()) >= 0 && depth <= 1 && getcmdwintype() == ''
enddef

export def IsEnabled(): bool
  return active && IsTarget()
enddef

def Reset()
  const options = configuration.GetInput()
  const previous_mode = current is null_object ? input_mode.HIRAGANA : current.GetInputMode()
  current = session.Session.new(compiled, options.sticky_key, {}, user_runtime.Get(), '',
    options.small_tsu_okuri_as_t, options.keyboard_layout, options.keyboard_layout_overrides,
    previous_mode, options.register_mode_conversions, options.dictionary_index)
  expected = getcmdline()
  position = getcmdpos()
  start = position - 1
  finish = start
enddef

def Check()
  if expected !=# getcmdline() || position != getcmdpos()
    Reset()
  endif
enddef

def Replace(text: string, close: bool)
  expected = strpart(expected, 0, start) .. text .. strpart(expected, finish)
  finish = start + strlen(text)
  position = finish + 1
  changing = true
  try
    setcmdline(expected, position)
  finally
    changing = false
  endtry
  if close
    start = finish
  endif
enddef

def Apply(results: list<session.Result>)
  for result in results
    if result.registration_requested
      Apply([current.CancelRegistration()])
    elseif result.commit_preedit
      Replace(result.text, true)
    elseif result.replace_preedit
      Replace(result.text, false)
    elseif result.state.in_preedit
      Replace(result.preedit_text, false)
    elseif result.text != ''
      Replace(result.text, true)
    endif
  endfor
enddef

def Pending()
  if current.InCandidate()
    return
  endif
  const snapshot = current.GetSnapshot()
  var text = snapshot.in_preedit ? current.RenderText(snapshot.reading .. snapshot.okuri) : ''
  for event in current.Pending()
    text ..= event.key
  endfor
  Replace(text, !snapshot.in_preedit && empty(current.Pending()))
enddef

def Refresh()
  if IsEnabled()
    const marker = current.InCandidate() ? 'candidate'
      : current.GetSnapshot().in_preedit || current.HasPendingModifier() ? 'modified' : ''
    candidates.Render(current.GetCandidatesInfo(), '', true)
    view.ShowCommandline(current.GetInputMode(), marker)
    redraw
  endif
enddef

def Commit()
  Check()
  const revision = user_runtime.Get().Revision()
  Apply(current.Commit())
  if configuration.GetStateAuto() && revision != user_runtime.Get().Revision()
    user_runtime.SaveAutomaticIfChanged(configuration.GetStatePath())
  endif
  Reset()
enddef

export def Disable()
  if !active
    return
  endif
  if IsTarget() && current isnot null_object
    Commit()
  endif
  active = false
  current = null_object
  candidates.Close()
  view.Close()
  for [lhs, native] in items(saved)
    if has_key(installed, lhs) && maparg(lhs, 'c', false, true) == installed[lhs]
      execute 'silent! cunmap <buffer> ' .. lhs
      if get(native, 'buffer', 0)
        mapset('c', false, native)
      endif
    endif
  endfor
  saved = {}
  installed = {}
enddef

export def Enable(definition: scheme.CompiledScheme)
  if !IsTarget() || active
    return
  endif
  compiled = definition
  current = null_object
  Reset()
  final keys_to_map: list<string> = []
  for code in range(0x20, 0x7e)
    keys_to_map->add(nr2char(code))
  endfor
  for code in range(1, 26)
    keys_to_map->add('<C-' .. nr2char(64 + code) .. '>')
  endfor
  keys_to_map->extend(['<CR>', '<BS>', '<Del>', '<Left>', '<Right>', '<Up>', '<Down>',
    '<Home>', '<End>', '<S-Tab>', '<PageUp>', '<PageDown>', '<Insert>', '<Esc>', '<C-Bslash>'])
  for key in keys(configuration.GetInput().mappings)
    keys_to_map->add(key)
  endfor
  for key in keys(definition.table.combinations)
    keys_to_map->add(key)
  endfor
  for rule in definition.specials
    keys_to_map->extend(rule.keys)
  endfor
  if configuration.GetInput().sticky_key != ''
    keys_to_map->add(configuration.GetInput().sticky_key)
  endif
  # Vim handles 'cedit' before dispatching ordinary editing keys. Leave
  # that key native; CmdlineLeavePre commits before the window takes over.
  const cedit = &cedit =~# '^\^.$' ? nr2char(char2nr(strpart(&cedit, 1)) - 64) : &cedit
  const cedit_lhs = cedit == '' ? '' : mapping.Lhs(cedit)
  active = true
  try
    for key in keys_to_map
      const lhs = mapping.Lhs(key)
      if lhs ==# cedit_lhs || has_key(saved, lhs)
        continue
      endif
      saved[lhs] = maparg(lhs, 'c', false, true)
      var argument = substitute(string(key), '<', '<lt>', 'g')
      argument = substitute(argument, '\\', '<Bslash>', 'g')
      argument = substitute(argument, '|', '<Bar>', 'g')
      # <silent> suppresses command-line redraw, hiding setcmdline() updates.
      execute 'cnoremap <buffer> ' .. lhs .. ' <ScriptCmd>Dispatch(' .. argument .. ')<CR>'
      installed[lhs] = maparg(lhs, 'c', false, true)
    endfor
    Refresh()
  catch
    const reason = v:exception
    Disable()
    throw reason
  endtry
enddef

export def Reinstall(lhs: string)
  if IsEnabled() && has_key(saved, lhs) && maparg(lhs, 'c', false, true) == saved[lhs]
    mapset('c', false, installed[lhs])
    Reset()
    Refresh()
  endif
enddef

def Native(key: string)
  Commit()
  const lhs = mapping.Lhs(key)
  if has_key(saved, lhs) && !empty(saved[lhs])
    # Let an existing mapping run in its original script context, then put
    # the guard back only if that mapping and this session still exist.
    execute 'silent! cunmap <buffer> ' .. lhs
    if get(saved[lhs], 'buffer', 0)
      mapset('c', false, saved[lhs])
    endif
    feedkeys(keycode.Encode(key) .. "\<Cmd>call caskk#commandline#Reinstall("
      .. string(lhs) .. ")\<CR>", 'im')
    return
  endif
  if index(['<C-R>', '<C-K>', '<C-V>', '<C-Q>', '<C-Bslash>'], key) >= 0
    candidates.Close()
    view.Close()
    feedkeys(keycode.Encode(key), 'int')
    return
  endif
  # Completion distinguishes a typed wildchar from a literal inserted Tab.
  feedkeys(keycode.Encode(key) .. "\<Cmd>call caskk#commandline#Resume()\<CR>",
    'int')
enddef

# Match Insert input: unavailable actions on printable keys remain IME input.
def Fallback(key: string)
  const literal = key ==# '<Space>' ? ' ' : key
  if strchars(literal) == 1 && char2nr(literal) >= 0x20 && char2nr(literal) != 0x7f
    const revision = user_runtime.Get().Revision()
    Apply(current.Feed(literal))
    Pending()
    if configuration.GetStateAuto() && revision != user_runtime.Get().Revision()
      user_runtime.SaveAutomaticIfChanged(configuration.GetStatePath())
    endif
    Refresh()
  else
    Native(key)
  endif
enddef

export def Resume()
  if IsEnabled()
    Reset()
    Refresh()
  endif
enddef

def Dispatch(key: string)
  if !IsEnabled()
    feedkeys(keycode.Encode(key), 'in')
    return
  endif
  Check()
  const revision = user_runtime.Get().Revision()
  const actions = configuration.GetInput().mappings
  const action = get(actions, key, get(actions, mapping.Lhs(key), ''))
  const busy = current.GetSnapshot().in_preedit || current.InCandidate()
    || !empty(current.Pending()) || current.HasPendingModifier()
  if key ==# '<Esc>' || key ==# '<C-C>'
    # A non-typed Esc executes the line in Vim; preserve the abort semantics.
    feedkeys(keycode.Encode(key), 'int')
    return
  elseif key ==# '<CR>' || key ==# '<C-M>' || action ==# 'Commit'
    if !busy
      Fallback(key)
      return
    endif
    Commit()
  elseif action != '' && current.IsSpecialContinuation(key)
    Apply(current.Feed(key))
    Pending()
  elseif (action ==# 'Convert' || action ==# 'NextCandidate') && busy
    Apply(current.InCandidate() ? [current.NextCandidate()]
      : current.StartConversion({}, user_runtime.Get()))
  elseif action ==# 'PreviousCandidate' && current.InCandidate()
    Apply([current.PreviousCandidate()])
  elseif (key ==# '<BS>' || key ==# '<C-H>') && action == ''
    if current.BackspacePending()
      Pending()
    else
      const result = current.BackspacePreedit()
      if result is null_object
        Native(key)
        return
      endif
      Apply([result])
    endif
  elseif mapping.ModeForAction(action) !=# ''
    const requested = mapping.ModeForAction(action)
    if current.CanChangeInputMode()
      current.SetInputMode(requested)
    elseif current.CanCommitPreeditAsMode(requested)
      Apply(current.CommitPreeditAsMode(requested))
    else
      Fallback(key)
      return
    endif
  elseif action != ''
    Fallback(key)
    return
  elseif strchars(key) == 1 && char2nr(key) >= 0x20
    Apply(current.Feed(key))
    Pending()
  else
    Native(key)
    return
  endif
  if configuration.GetStateAuto() && revision != user_runtime.Get().Revision()
    user_runtime.SaveAutomaticIfChanged(configuration.GetStatePath())
  endif
  Refresh()
enddef

def Enter()
  if active && depth == 1
    Commit()
    candidates.Close()
    view.Close()
  endif
  depth += 1
enddef

def BeforeLeave()
  if IsEnabled() && v:char !=# "\<Esc>" && v:char !=# "\<C-C>"
    Commit()
  endif
enddef

def Leave()
  if depth <= 1
    # The leaving line may already be aborted; do not learn or rewrite it.
    current = null_object
    Disable()
  endif
  depth = max([0, depth - 1])
enddef

def Changed()
  if IsEnabled() && !changing
    Check()
    Refresh()
  endif
enddef

augroup caskk_commandline
  autocmd!
  autocmd CmdlineEnter * Enter()
  autocmd CmdlineLeavePre * BeforeLeave()
  autocmd CmdlineLeave * Leave()
  autocmd CmdlineChanged * Changed()
  autocmd CmdwinEnter * Disable()
augroup END
