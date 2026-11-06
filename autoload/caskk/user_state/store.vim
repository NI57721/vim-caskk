vim9script

import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/user_state/codec.vim' as codec

# Decode fully before the caller can replace its current state with Restore().
export def Load(path: string): user_state.Snapshot
  try
    const lines = blob2str(readblob(path), {encoding: 'utf-8'})
    return codec.Decode(lines)
  catch
    throw 'caskk: cannot load user state: ' .. path .. ': ' .. v:exception
  endtry
enddef

export def Save(path: string, snapshot: user_state.Snapshot)
  try
    # Validate and encode before touching the destination directory.
    const bytes = str2blob(codec.Encode(snapshot), {encoding: 'utf-8'})
    const parent = fnamemodify(path, ':h')
    if !mkdir(parent, 'p', 0o700)
      throw 'cannot create parent directory'
    endif
    # An exclusively created directory avoids reusing another writer's file.
    # Keep it beside the destination so the final rename stays on one filesystem.
    const temporary = path .. '.tmp-' .. getpid() .. '-' .. fnamemodify(tempname(), ':t')
    if !mkdir(temporary, '', 0o700)
      throw 'cannot create temporary directory'
    endif
    defer delete(temporary, 'rf')
    const staged = temporary .. '/state'
    if writefile(bytes, staged, 's') != 0
      throw 'cannot write temporary file'
    endif
    if setfperm(staged, 'rw-------') != 1
      throw 'cannot set user state file permissions'
    endif
    if rename(staged, path) != 0
      throw 'cannot replace destination'
    endif
  catch
    throw 'caskk: cannot save user state: ' .. path .. ': ' .. v:exception
  endtry
enddef
