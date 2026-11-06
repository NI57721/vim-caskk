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

  def new(lines: list<string>)
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
    final okuri_lines: list<number> = []
    final plain_lines: list<number> = []
    final fallback: dict<dictionary.Entry> = {}
    if this._sectioned
      for index in range(okuri_header + 1, plain_header - 1)
        if EntryKey(lines[index]) !=# ''
          okuri_lines->add(index)
        endif
      endfor
      for index in range(plain_header + 1, len(lines) - 1)
        if EntryKey(lines[index]) !=# ''
          plain_lines->add(index)
        endif
      endfor
    else
      for line in lines
        try
          const entry = parser.ParseLine(line)
          if entry isnot null_object
            if has_key(fallback, entry.lookup_key)
              fallback[entry.lookup_key] = merger.Merge([[fallback[entry.lookup_key], entry]])[entry.lookup_key]
            else
              fallback[entry.lookup_key] = entry
            endif
          endif
        catch
          # Keep the loader's behavior of skipping lines outside our supported subset.
        endtry
      endfor
    endif
    this._okuri_lines = okuri_lines
    this._plain_lines = plain_lines
    this._fallback = fallback
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

export class Database
  const _sources: list<SourceData>

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
endclass

export def SourceFromLines(lines: list<string>): SourceData
  return SourceData.new(lines)
enddef
