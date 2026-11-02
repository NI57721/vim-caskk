vim9script

import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/store.vim' as store

# Public activations share user choices independently of input configuration.
const current = user_state.State.new()
var initialized_path: string = ''

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
  current.Restore(snapshot)
  initialized_path = path
enddef

export def Save(path: string)
  CheckPath(path)
  store.Save(path, current.GetSnapshot())
  initialized_path = path
enddef

export def InitializeAutomatic(path: string)
  CheckPath(path)
  if initialized_path ==# path
    return
  endif
  if getftype(path) != ''
    Load(path)
  else
    # A first run keeps the current in-memory state until the initial save.
    initialized_path = path
  endif
enddef

export def SaveAutomatic(path: string)
  if path != '' && initialized_path ==# path
    Save(path)
  endif
enddef
