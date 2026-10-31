vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/candidate/ranking.vim' as ranking
import autoload 'caskk/dictionary/merge.vim' as merger

# Encode the pair to avoid collisions from concatenating reading and okuri.
def Identity(query: dictionary.Query): string
  return json_encode([query.reading, query.exact_okuri])
enddef

# In-memory user entries and preferences; system candidates remain read-only.
export class State
  var _entries: dict<list<dictionary.Candidate>> = {}
  var _mru: dict<list<string>> = {}
  var _pinned: dict<string> = {}
  var _demoted: dict<list<string>> = {}

  def new()
  enddef

  def AddEntry(query: dictionary.Query, candidate: dictionary.Candidate)
    const key = Identity(query)
    const merged = merger.Merge([
      [dictionary.Entry.new(query.lookup_key, get(this._entries, key, []))],
      [dictionary.Entry.new(query.lookup_key, [candidate])],
    ])
    this._entries[key] = merged[query.lookup_key].candidates
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
    if empty(remaining)
      remove(this._entries, key)
    else
      this._entries[key] = remaining
    endif
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
    this._mru[key] = history
  enddef

  def Pin(query: dictionary.Query, text: string)
    const key = Identity(query)
    this._pinned[key] = text
    if has_key(this._demoted, key)
      const position = index(this._demoted[key], text)
      if position >= 0
        remove(this._demoted[key], position)
      endif
    endif
  enddef

  def Demote(query: dictionary.Query, text: string)
    const key = Identity(query)
    if get(this._pinned, key, '') ==# text
      remove(this._pinned, key)
    endif
    if !has_key(this._demoted, key)
      this._demoted[key] = []
    endif
    if index(this._demoted[key], text) == -1
      this._demoted[key]->add(text)
    endif
  enddef

  # Clear explicit tier overrides for one candidate; retain automatic MRU history.
  def Reset(query: dictionary.Query, text: string)
    const key = Identity(query)
    if has_key(this._pinned, key) && this._pinned[key] ==# text
      remove(this._pinned, key)
    endif
    if has_key(this._demoted, key)
      const position = index(this._demoted[key], text)
      if position >= 0
        remove(this._demoted[key], position)
      endif
    endif
  enddef

  def Rank(query: dictionary.Query, candidates: list<dictionary.Candidate>): list<dictionary.Candidate>
    const key = Identity(query)
    var combined = candidates
    if has_key(this._entries, key)
      const merged = merger.Merge([
        [dictionary.Entry.new(query.lookup_key, candidates)],
        [dictionary.Entry.new(query.lookup_key, this._entries[key])],
      ])
      combined = merged[query.lookup_key].candidates
    endif
    return ranking.Rank(combined, get(this._pinned, key, ''),
      get(this._mru, key, []), get(this._demoted, key, []))
  enddef
endclass
