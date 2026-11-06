vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger

const OKURI_HEADER = ';; okuri-ari entries.'
const PLAIN_HEADER = ';; okuri-nasi entries.'

def EntryKey(line: string): string
  if line =~# '^\s*;;' || line =~# '^\s*$'
    return ''
  endif
  const fields = matchlist(line, '^\([^[:space:]]\+\)[ \t]\+/')
  return empty(fields) ? '' : fields[1]
enddef

def CompareKeys(left: string, right: string): number
  const left_codes = str2list(left, true)
  const right_codes = str2list(right, true)
  const common = min([len(left_codes), len(right_codes)])
  for offset in range(common)
    if left_codes[offset] != right_codes[offset]
      return left_codes[offset] < right_codes[offset] ? -1 : 1
    endif
  endfor
  if len(left_codes) == len(right_codes)
    return 0
  endif
  return len(left_codes) < len(right_codes) ? -1 : 1
enddef

export class SourceData
  const _lines: list<string>
  const _okuri_lines: list<number>
  const _plain_lines: list<number>
  const _sectioned: bool
  const _fallback: dict<dictionary.Entry>

  def new(lines: list<string>, okuri_lines: list<number> = [], plain_lines: list<number> = [],
      sectioned: bool = false, fallback: dict<dictionary.Entry> = {}, prepared: bool = false)
    if prepared
      this._lines = lines
      this._sectioned = sectioned
      this._okuri_lines = okuri_lines
      this._plain_lines = plain_lines
      this._fallback = fallback
      return
    endif
    this._lines = copy(lines)
    var okuri_header = -1
    var plain_header = -1
    for index in range(len(lines))
      if lines[index] =~# '^;; okuri-ari entries\.'
        okuri_header = index
      elseif lines[index] =~# '^;; okuri-nasi entries\.'
        plain_header = index
      endif
    endfor
    this._sectioned = okuri_header >= 0 && plain_header > okuri_header
    final indexed_okuri_lines: list<number> = []
    final indexed_plain_lines: list<number> = []
    final fallback_entries: dict<dictionary.Entry> = {}
    if this._sectioned
      for index in range(okuri_header + 1, plain_header - 1)
        if EntryKey(lines[index]) !=# ''
          indexed_okuri_lines->add(index)
        endif
      endfor
      for index in range(plain_header + 1, len(lines) - 1)
        if EntryKey(lines[index]) !=# ''
          indexed_plain_lines->add(index)
        endif
      endfor
    else
      for line in lines
        try
          const entry = parser.ParseLine(line)
          if entry isnot null_object
            if has_key(fallback_entries, entry.lookup_key)
              fallback_entries[entry.lookup_key] = merger.Merge([[fallback_entries[entry.lookup_key], entry]])[entry.lookup_key]
            else
              fallback_entries[entry.lookup_key] = entry
            endif
          endif
        catch
          # Keep the loader's behavior of skipping lines outside our supported subset.
        endtry
      endfor
    endif
    this._okuri_lines = indexed_okuri_lines
    this._plain_lines = indexed_plain_lines
    this._fallback = fallback_entries
  enddef

  def _ParseMatches(lines: list<number>, key: string, low: number, high: number): list<dictionary.Entry>
    final entries: list<dictionary.Entry> = []
    if low < 0 || high >= len(lines) || low > high
      return entries
    endif
    for position in range(low, high)
      try
        const entry = parser.ParseLine(this._lines[lines[position]])
        if entry isnot null_object
          entries->add(entry)
        endif
      catch
        # An invalid row with this key does not hide a valid duplicate row.
      endtry
    endfor
    return entries
  enddef

  def Lookup(key: string, has_okuri: bool): list<dictionary.Entry>
    if !this._sectioned
      return has_key(this._fallback, key) ? [this._fallback[key]] : []
    endif
    const lines = has_okuri ? this._okuri_lines : this._plain_lines
    const descending = has_okuri
    var low = 0
    var high = len(lines) - 1
    while low <= high
      const middle = (low + high) / 2
      const middle_key = EntryKey(this._lines[lines[middle]])
      const comparison = CompareKeys(middle_key, key)
      if comparison == 0
        var first = middle
        var last = middle
        while first > 0 && EntryKey(this._lines[lines[first - 1]]) ==# key
          first -= 1
        endwhile
        while last + 1 < len(lines) && EntryKey(this._lines[lines[last + 1]]) ==# key
          last += 1
        endwhile
        return this._ParseMatches(lines, key, first, last)
      elseif (descending && comparison > 0) || (!descending && comparison < 0)
        low = middle + 1
      else
        high = middle - 1
      endif
    endwhile
    return []
  enddef
endclass

# Incremental indexing work. Each Step inspects or parses at most max_lines
# physical rows, allowing callers to schedule the next slice with a timer.
export class Builder
  const _lines: list<string>
  var _position: number = 0
  var _phase: string = 'scan'
  var _okuri_header: number = -1
  var _plain_header: number = -1
  var _okuri_lines: list<number> = []
  var _plain_lines: list<number> = []
  var _fallback: dict<dictionary.Entry> = {}
  var _result: SourceData = null_object

  def new(lines: list<string>)
    this._lines = lines
  enddef

  def IsDone(): bool
    return this._phase ==# 'done'
  enddef

  def Result(): SourceData
    if !this.IsDone()
      throw 'caskk: dictionary index is not complete'
    endif
    return this._result
  enddef

  def _FinishScan()
    if this._okuri_header >= 0 && this._plain_header > this._okuri_header
      this._phase = 'sections'
    else
      this._position = 0
      this._phase = 'fallback'
    endif
  enddef

  def _ParseFallbackLine(line: string)
    try
      const entry = parser.ParseLine(line)
      if entry isnot null_object
        if has_key(this._fallback, entry.lookup_key)
          this._fallback[entry.lookup_key] = merger.Merge([[this._fallback[entry.lookup_key], entry]])[entry.lookup_key]
        else
          this._fallback[entry.lookup_key] = entry
        endif
      endif
    catch
      # Ignore rows outside the supported dictionary subset.
    endtry
  enddef

  def _Finish()
    const sectioned = this._phase ==# 'sections'
    this._result = SourceData.new(this._lines, this._okuri_lines, this._plain_lines,
      sectioned, this._fallback, true)
    this._phase = 'done'
  enddef

  def Step(max_lines: number): bool
    if max_lines <= 0
      throw 'caskk: dictionary index step must be positive'
    endif
    if this.IsDone()
      return true
    endif
    var processed = 0
    while processed < max_lines
      if this._phase ==# 'scan'
        if this._position >= len(this._lines)
          this._FinishScan()
          if this._phase ==# 'sections'
            this._position = 0
          endif
          continue
        endif
        const line = this._lines[this._position]
        if line =~# '^;; okuri-ari entries\.'
          this._okuri_header = this._position
        elseif line =~# '^;; okuri-nasi entries\.'
          this._plain_header = this._position
        endif
        this._position += 1
      elseif this._phase ==# 'sections'
        if this._position >= len(this._lines)
          this._Finish()
          break
        endif
        const position = this._position
        if position > this._okuri_header && position < this._plain_header
          if EntryKey(this._lines[position]) !=# ''
            this._okuri_lines->add(position)
          endif
        elseif position > this._plain_header
          if EntryKey(this._lines[position]) !=# ''
            this._plain_lines->add(position)
          endif
        endif
        this._position += 1
      elseif this._phase ==# 'fallback'
        if this._position >= len(this._lines)
          this._Finish()
          break
        endif
        this._ParseFallbackLine(this._lines[this._position])
        this._position += 1
      endif
      processed += 1
    endwhile
    return this.IsDone()
  enddef
endclass

export class Database
  var _sources: list<SourceData>
  var _ready: bool = true

  def new(sources: list<SourceData>)
    this._sources = copy(sources)
  enddef

  def Lookup(query: dictionary.Query): list<dictionary.Candidate>
    final entries: list<dictionary.Entry> = []
    for source in this._sources
      entries->extend(source.Lookup(query.lookup_key, query.exact_okuri !=# ''))
    endfor
    if empty(entries)
      return []
    elseif len(entries) == 1
      final seen: dict<bool> = {}
      var duplicate = false
      for candidate in entries[0].candidates
        if has_key(seen, candidate.text)
          duplicate = true
          break
        endif
        seen[candidate.text] = true
      endfor
      if !duplicate
        return copy(entries[0].candidates)
      endif
    endif
    const merged = merger.Merge([entries])
    return has_key(merged, query.lookup_key) ? copy(merged[query.lookup_key].candidates) : []
  enddef

  def IsReady(): bool
    return this._ready
  enddef

  def MarkLoading()
    this._ready = false
  enddef

  def ReplaceWith(database: Database)
    this._sources = copy(database._sources)
    this._ready = true
  enddef
endclass

export def SourceFromLines(lines: list<string>): SourceData
  const builder = Builder.new(lines)
  while !builder.Step(max([1, len(lines)]))
  endwhile
  return builder.Result()
enddef
