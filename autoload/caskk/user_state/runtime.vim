vim9script

import autoload 'caskk/user_state.vim' as user_state

# Public activations share user choices independently of input configuration.
const current = user_state.State.new()

export def Get(): user_state.State
  return current
enddef
