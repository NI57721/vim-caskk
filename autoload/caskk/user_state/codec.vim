vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/user_state.vim' as user_state

# JSON lines of string arrays. Header: ["caskk-user-state", "1"].
# Records: [kind, reading, exact_okuri, ...values]. Entry values are text,
# then annotations; mru/demoted values are ordered texts; pin has one text.
def Strings(line: string): list<string>
  try
    const decoded: list<string> = json_decode(line)
    return decoded
  catch
    throw 'caskk: invalid user state: expected a JSON array of strings'
  endtry
enddef

def CheckIdentity(pair: list<string>)
  if len(pair) != 2 || strchars(pair[1]) > 1
    throw 'caskk: invalid user state: expected reading and one-character exact okuri'
  endif
enddef

def CheckUnique(texts: list<string>)
  final seen: dict<bool> = {}
  for text in texts
    if has_key(seen, text)
      throw 'caskk: invalid user state: repeated candidate text'
    endif
    seen[text] = true
  endfor
enddef

export def Decode(lines: list<string>): user_state.Snapshot
  if empty(lines) || Strings(lines[0]) !=# ['caskk-user-state', '1']
    throw 'caskk: invalid user state: missing or unsupported schema header'
  endif
  final entries: dict<list<dictionary.Candidate>> = {}
  final mru: dict<list<string>> = {}
  final pinned: dict<string> = {}
  final demoted: dict<list<string>> = {}
  for line in lines[1 :]
    const record = Strings(line)
    if len(record) < 3
      throw 'caskk: invalid user state: incomplete record'
    endif
    const pair = record[1 : 2]
    CheckIdentity(pair)
    const key = json_encode(pair)
    const kind = record[0]
    const values = record[3 :]
    if kind ==# 'entry'
      if empty(values)
        throw 'caskk: invalid user state: entry has no candidate text'
      endif
      if !has_key(entries, key)
        entries[key] = []
      endif
      for candidate in entries[key]
        if candidate.text ==# values[0]
          throw 'caskk: invalid user state: repeated user entry'
        endif
      endfor
      entries[key]->add(dictionary.Candidate.new(values[0], values[1 :]))
    elseif kind ==# 'mru' || kind ==# 'demoted'
      CheckUnique(values)
      if kind ==# 'mru'
        if has_key(mru, key)
          throw 'caskk: invalid user state: repeated MRU record'
        endif
        mru[key] = values
      else
        if has_key(demoted, key)
          throw 'caskk: invalid user state: repeated demotion record'
        endif
        demoted[key] = values
      endif
    elseif kind ==# 'pin'
      if len(values) != 1 || has_key(pinned, key)
        throw 'caskk: invalid user state: invalid or repeated pin record'
      endif
      pinned[key] = values[0]
    else
      throw 'caskk: invalid user state: unknown record kind: ' .. kind
    endif
  endfor
  for [key, text] in items(pinned)
    if index(get(demoted, key, []), text) >= 0
      throw 'caskk: invalid user state: candidate is both pinned and demoted'
    endif
  endfor
  return user_state.Snapshot.new(1, entries, mru, pinned, demoted)
enddef

def AddOrderedRecords(lines: list<string>, kind: string, groups: dict<list<string>>)
  for key in sort(keys(groups))
    const pair = Strings(key)
    CheckIdentity(pair)
    lines->add(json_encode([kind] + pair + groups[key]))
  endfor
enddef

export def Encode(snapshot: user_state.Snapshot): list<string>
  if snapshot.version != 1
    throw 'caskk: invalid user state: unsupported schema version: ' .. snapshot.version
  endif
  final lines: list<string> = [json_encode(['caskk-user-state', '1'])]
  for key in sort(keys(snapshot.entries))
    const pair = Strings(key)
    CheckIdentity(pair)
    for candidate in snapshot.entries[key]
      lines->add(json_encode(['entry'] + pair + [candidate.text] + candidate.annotations))
    endfor
  endfor
  AddOrderedRecords(lines, 'mru', snapshot.mru)
  for key in sort(keys(snapshot.pinned))
    const pair = Strings(key)
    CheckIdentity(pair)
    lines->add(json_encode(['pin'] + pair + [snapshot.pinned[key]]))
  endfor
  AddOrderedRecords(lines, 'demoted', snapshot.demoted)
  # Apply the same structural validation to snapshots supplied by callers.
  Decode(lines)
  return lines
enddef
