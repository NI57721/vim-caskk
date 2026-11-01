vim9script

import autoload 'caskk/config.vim' as configuration

# Currently the public settings cover highlight.preedit attributes and colors.
export def Config(options: dict<dict<dict<string>>>)
  configuration.Configure(options)
enddef
