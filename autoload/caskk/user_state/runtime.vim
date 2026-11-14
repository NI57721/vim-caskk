vim9script

import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/store.vim' as store

# Public activations share user choices independently of input configuration.
const current = user_state.State.new()
var initialized_path: string = ''
var observed_contents: blob = 0z
var observed_exists: bool = false
var last_automatic_attempt_revision: number = -1

export def Get(): user_state.State
  return current
enddef

def CheckPath(path: string)
  if path == ''
    throw 'caskk: user state path is not configured'
  endif
enddef

export def Load(path: string)
  CheckPath(path)
  if initialized_path ==# path
    initialized_path = ''
  endif
  const snapshot = store.Load(path)
  observed_contents = readblob(path)
  observed_exists = true
  current.Restore(snapshot)
  initialized_path = path
  last_automatic_attempt_revision = current.Revision()
enddef

export def Save(path: string)
  CheckPath(path)
  store.Save(path, current.GetSnapshot())
  observed_contents = readblob(path)
  observed_exists = true
  initialized_path = path
  last_automatic_attempt_revision = current.Revision()
enddef

export def InitializeAutomatic(path: string)
  CheckPath(path)
  if initialized_path ==# path
    return
  endif
  if getftype(path) != ''
    Load(path)
  else
    observed_contents = 0z
    observed_exists = false
    # A first run keeps the current in-memory state until the initial save.
    initialized_path = path
    last_automatic_attempt_revision = current.Revision()
  endif
enddef

# Saved manual edits take precedence over pending in-memory learning.
# Load validates before Restore and revokes automatic saving on failure.
export def RefreshExternal(path: string): bool
  if path == '' || initialized_path !=# path || !filereadable(path)
    return false
  endif
  if observed_exists && readblob(path) == observed_contents
    return false
  endif
  Load(path)
  return true
enddef

export def SaveAutomatic(path: string)
  if path != '' && initialized_path ==# path && !RefreshExternal(path)
    Save(path)
  endif
enddef

export def SaveAutomaticIfChanged(path: string): string
  if path == '' || initialized_path !=# path
    return ''
  endif
  try
    if RefreshExternal(path)
      return ''
    endif
  catch
    return v:exception
  endtry
  const revision = current.Revision()
  if revision == last_automatic_attempt_revision
    return ''
  endif
  last_automatic_attempt_revision = revision
  try
    Save(path)
    return ''
  catch
    return v:exception
  endtry
enddef
