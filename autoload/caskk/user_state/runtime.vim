vim9script

import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/store.vim' as store

# Public activations share user choices independently of input configuration.
const current = user_state.State.new()

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
  const snapshot = store.Load(path)
  current.Restore(snapshot)
enddef

export def Save(path: string)
  CheckPath(path)
  store.Save(path, current.GetSnapshot())
enddef
