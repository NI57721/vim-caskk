vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/candidate/ranking.vim' as ranking
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/lookup.vim' as lookup

# Encode the pair to avoid collisions from concatenating reading and okuri.
def Identity(query: dictionary.Query): string
  return json_encode([query.reading, query.exact_okuri])
enddef

const SCHEMA_VERSION = 1

def CopyEntries(entries: dict<list<dictionary.Candidate>>): dict<list<dictionary.Candidate>>
  final copied: dict<list<dictionary.Candidate>> = {}
  for [key, candidates] in items(entries)
    copied[key] = []
    for candidate in candidates
      copied[key]->add(dictionary.Candidate.new(candidate.text, candidate.annotations, candidate.has_plain_source ? 1 : 0))
    endfor
  endfor
  return copied
enddef

# Typed transfer data, not a file format. Keys encode [reading, exact_okuri].
export class Snapshot
  const version: number
  const entries: dict<list<dictionary.Candidate>>
  const mru: dict<list<string>>
  const pinned: dict<string>
  const demoted: dict<list<string>>

  def new(this.version, entries: dict<list<dictionary.Candidate>>, mru: dict<list<string>>, pinned: dict<string>, demoted: dict<list<string>>)
    this.entries = CopyEntries(entries)
    this.mru = deepcopy(mru)
    this.pinned = copy(pinned)
    this.demoted = deepcopy(demoted)
  enddef
endclass

# In-memory user entries and preferences; system candidates remain read-only.
export class State
  var _entries: dict<list<dictionary.Candidate>> = {}
  var _mru: dict<list<string>> = {}
  var _pinned: dict<string> = {}
  var _demoted: dict<list<string>> = {}
  var _revision: number = 0

  def new()
  enddef

  def GetSnapshot(): Snapshot
    return Snapshot.new(SCHEMA_VERSION, this._entries, this._mru, this._pinned, this._demoted)
  enddef

  # Completion reads one registered identity at a time, guarded by Revision().
  def RegisteredIdentities(): list<string>
    return keys(this._entries)
  enddef

  def RegisteredCandidates(identity: string): list<dictionary.Candidate>
    return copy(get(this._entries, identity, []))
  enddef

  # Candidates already include registered entries; only apply their preferences.
  def HistoryIndex(query: dictionary.Query, text: string): number
    return index(get(this._mru, Identity(query), []), text)
  enddef

  def RankCandidates(query: dictionary.Query, candidates: list<dictionary.Candidate>): list<dictionary.Candidate>
    const key = Identity(query)
    return ranking.Rank(candidates, get(this._pinned, key, ''),
      get(this._mru, key, []), get(this._demoted, key, []))
  enddef

  def Revision(): number
    return this._revision
  enddef

  def Restore(snapshot: Snapshot)
    if snapshot.version != SCHEMA_VERSION
      throw 'caskk: unsupported user state schema version: ' .. snapshot.version
    endif
    # Copy everything before replacing the current state.
    final entries = CopyEntries(snapshot.entries)
    final mru = deepcopy(snapshot.mru)
    final pinned = copy(snapshot.pinned)
    final demoted = deepcopy(snapshot.demoted)
    this._entries = entries
    this._mru = mru
    this._pinned = pinned
    this._demoted = demoted
    this._revision += 1
  enddef

  def _Changed()
    this._revision += 1
  enddef

  def _SameCandidates(left: list<dictionary.Candidate>, right: list<dictionary.Candidate>): bool
    if len(left) != len(right)
      return false
    endif
    if empty(left)
      return true
    endif
    for index in range(len(left))
      if left[index].text !=# right[index].text || left[index].annotations !=# right[index].annotations
        return false
      endif
    endfor
    return true
  enddef

  def AddEntry(query: dictionary.Query, candidate: dictionary.Candidate)
    const key = Identity(query)
    const merged = merger.Merge([
      [dictionary.Entry.new(query.lookup_key, get(this._entries, key, []))],
      [dictionary.Entry.new(query.lookup_key, [candidate])],
    ])
    const candidates = merged[query.lookup_key].candidates
    if !this._SameCandidates(get(this._entries, key, []), candidates)
      this._entries[key] = candidates
      this._Changed()
    endif
  enddef

  # Remove only the registered source; ranking preferences remain independent.
  def DeleteEntry(query: dictionary.Query, text: string)
    const key = Identity(query)
    if !has_key(this._entries, key)
      return
    endif
    final remaining: list<dictionary.Candidate> = []
    for candidate in this._entries[key]
      if candidate.text !=# text
        remaining->add(candidate)
      endif
    endfor
    if len(remaining) == len(this._entries[key])
      return
    endif
    if empty(remaining)
      remove(this._entries, key)
    else
      this._entries[key] = remaining
    endif
    this._Changed()
  enddef

  def HasEntryForLookup(query: dictionary.Query, text: string): bool
    for identity in sort(keys(this._entries))
      const candidates = this._entries[identity]
      const pair: list<string> = json_decode(identity)
      if lookup.CreateQuery(pair[0], pair[1]).lookup_key ==# query.lookup_key
          && index(mapnew(candidates, (_, candidate) => candidate.text), text) >= 0
        return true
      endif
    endfor
    return false
  enddef

  def DeleteEntryForLookup(query: dictionary.Query, text: string): bool
    var deleted = false
    for identity in sort(keys(this._entries))
      const pair: list<string> = json_decode(identity)
      if lookup.CreateQuery(pair[0], pair[1]).lookup_key ==# query.lookup_key
          && index(mapnew(this._entries[identity], (_, candidate) => candidate.text), text) >= 0
        this.DeleteEntry(lookup.CreateQuery(pair[0], pair[1]), text)
        deleted = true
      endif
    endfor
    return deleted
  enddef

  def Learn(query: dictionary.Query, text: string)
    const key = Identity(query)
    if get(this._pinned, key, '') ==# text || index(get(this._demoted, key, []), text) >= 0
      return
    endif
    final history: list<string> = [text]
    for previous in get(this._mru, key, [])
      if previous !=# text
        history->add(previous)
      endif
    endfor
    if get(this._mru, key, []) ==# history
      return
    endif
    this._mru[key] = history
    this._Changed()
  enddef

  def Pin(query: dictionary.Query, text: string)
    const key = Identity(query)
    if get(this._pinned, key, '') ==# text && index(get(this._demoted, key, []), text) < 0
      return
    endif
    this._pinned[key] = text
    if has_key(this._demoted, key)
      const position = index(this._demoted[key], text)
      if position >= 0
        remove(this._demoted[key], position)
      endif
      if empty(this._demoted[key])
        remove(this._demoted, key)
      endif
    endif
    this._Changed()
  enddef

  def Demote(query: dictionary.Query, text: string)
    const key = Identity(query)
    if index(get(this._demoted, key, []), text) >= 0 && get(this._pinned, key, '') !=# text
      return
    endif
    if get(this._pinned, key, '') ==# text
      remove(this._pinned, key)
    endif
    if !has_key(this._demoted, key)
      this._demoted[key] = []
    endif
    if index(this._demoted[key], text) == -1
      this._demoted[key]->add(text)
    endif
    this._Changed()
  enddef

  # Clear explicit tier overrides for one candidate; retain automatic MRU history.
  def Reset(query: dictionary.Query, text: string)
    const key = Identity(query)
    var changed = false
    if has_key(this._pinned, key) && this._pinned[key] ==# text
      remove(this._pinned, key)
      changed = true
    endif
    if has_key(this._demoted, key)
      const position = index(this._demoted[key], text)
      if position >= 0
        remove(this._demoted[key], position)
        changed = true
      endif
      if empty(this._demoted[key])
        remove(this._demoted, key)
      endif
    endif
    if changed
      this._Changed()
    endif
  enddef

  def GetCandidateTier(query: dictionary.Query, text: string): string
    const key = Identity(query)
    if get(this._pinned, key, '') ==# text
      return 'pinned'
    elseif index(get(this._demoted, key, []), text) >= 0
      return 'demoted'
    endif
    return ''
  enddef

  def TogglePin(query: dictionary.Query, text: string): string
    if this.GetCandidateTier(query, text) ==# 'pinned'
      this.Reset(query, text)
    else
      this.Pin(query, text)
    endif
    return this.GetCandidateTier(query, text)
  enddef

  def ToggleDemote(query: dictionary.Query, text: string): string
    if this.GetCandidateTier(query, text) ==# 'demoted'
      this.Reset(query, text)
    else
      this.Demote(query, text)
    endif
    return this.GetCandidateTier(query, text)
  enddef

  def Rank(query: dictionary.Query, candidates: list<dictionary.Candidate>): list<dictionary.Candidate>
    final registered: list<dictionary.Entry> = []
    for identity in sort(keys(this._entries))
      const entries = this._entries[identity]
      const pair: list<string> = json_decode(identity)
      if lookup.CreateQuery(pair[0], pair[1]).lookup_key ==# query.lookup_key
        registered->add(dictionary.Entry.new(query.lookup_key, entries))
      endif
    endfor
    const merged = merger.Merge([[dictionary.Entry.new(query.lookup_key, candidates)], registered])
    final combined: list<dictionary.Candidate> = get(merged, query.lookup_key, dictionary.Entry.new(query.lookup_key, [])).candidates
    return this.RankCandidates(query, query.exact_okuri == ''
      ? filter(copy(combined), (_, candidate) => candidate.has_plain_source) : combined)
  enddef
endclass
