vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/user_state.vim' as user_state

const OKURI_HEADER = ';; okuri-ari entries.'
const PLAIN_HEADER = ';; okuri-nasi entries.'

def CompareDescending(left: string, right: string): number
  if left ==# right
    return 0
  endif
  return left ># right ? -1 : 1
enddef

def EntryLine(entry: dictionary.Entry): string
  final candidates: list<string> = []
  for candidate in entry.candidates
    if candidate.text =~# '[/;\r\n]' || join(candidate.annotations, '') =~# '[/\r\n]'
      throw 'caskk: user dictionary entry contains an unsupported SKK delimiter'
    endif
    var text = candidate.text
    if !empty(candidate.annotations)
      text ..= ';' .. join(candidate.annotations, ';')
    endif
    candidates->add(text)
  endfor
  return entry.lookup_key .. ' /' .. join(candidates, '/') .. '/'
enddef

# Serialize only registered user entries. Candidate preferences and learning
# history are private runtime state and have no SKK dictionary representation.
export def Format(snapshot: user_state.Snapshot): list<string>
  final sources: list<dictionary.Entry> = []
  final okuri_keys: dict<bool> = {}
  final plain_keys: dict<bool> = {}
  for identity in sort(keys(snapshot.entries))
    const pair: list<string> = json_decode(identity)
    const query = lookup.CreateQuery(pair[0], pair[1])
    sources->add(dictionary.Entry.new(query.lookup_key, snapshot.entries[identity]))
    if query.exact_okuri !=# ''
      okuri_keys[query.lookup_key] = true
    else
      plain_keys[query.lookup_key] = true
    endif
  endfor
  const merged = merger.Merge([sources])
  final lines = [OKURI_HEADER]
  const sorted_okuri = sort(keys(okuri_keys), function('CompareDescending'))
  for key in sorted_okuri
    lines->add(EntryLine(merged[key]))
  endfor
  lines->add(PLAIN_HEADER)
  for key in sort(keys(plain_keys))
    lines->add(EntryLine(merged[key]))
  endfor
  return lines
enddef

export def Write(path: string, snapshot: user_state.Snapshot)
  if path ==# ''
    throw 'caskk: user dictionary export path must not be empty'
  endif
  const lines = Format(snapshot)
  const parent = fnamemodify(path, ':h')
  if !mkdir(parent, 'p', 0o755)
    throw 'caskk: cannot create user dictionary export directory: ' .. parent
  endif
  const temporary = path .. '.tmp-' .. getpid() .. '-' .. fnamemodify(tempname(), ':t')
  defer delete(temporary)
  if writefile(lines, temporary) != 0
    throw 'caskk: cannot write user dictionary export: ' .. path
  endif
  if rename(temporary, path) != 0
    throw 'caskk: cannot replace user dictionary export: ' .. path
  endif
enddef
