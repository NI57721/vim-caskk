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

# SKK keys are sorted as bytes in the source encoding, which may differ from
# Unicode codepoint order (for example, prolonged sound marks in EUC-JP).
def EncodedBytes(value: string, encoding: string): list<number>
  const encoded = iconv(value, &encoding, encoding)
  final bytes: list<number> = []
  for offset in range(strlen(encoded))
    bytes->add(char2nr(strpart(encoded, offset, 1), true))
  endfor
  return bytes
enddef

def CompareKeys(left: string, right: string, encoding: string): number
  const left_codes = EncodedBytes(left, encoding)
  const right_codes = EncodedBytes(right, encoding)
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

# Discover actual headers, using entry kinds only to choose probe directions.
# A failed binary search returns to a scan, so unusual rows cannot fabricate a
# section boundary. Each Step inspects at most max_lines physical rows.
class SectionSearch
  const _lines: list<string>
  var okuri_header: number = -1
  var plain_header: number = -1
  var _phase: string = 'scan'
  var _position: number = 0
  var _attempted: bool = false
  var _low: number = 0
  var _high: number = -1
  var _middle: number = 0

  def new(this._lines)
  enddef

  def _PrepareProbe()
    if this._low > this._high
      this._phase = 'scan'
      this._position = this.okuri_header + 1
    else
      this._middle = (this._low + this._high) / 2
      this._position = this._middle
    endif
  enddef

  def Step(max_lines: number): bool
    var inspected = 0
    while inspected < max_lines && this._phase !=# 'done'
      if this._phase ==# 'scan'
        if this._position >= len(this._lines)
          this._phase = 'done'
          break
        endif
        const line = this._lines[this._position]
        if stridx(line, OKURI_HEADER) == 0
          this.okuri_header = this._position
          if !this._attempted && this.plain_header < 0
            this._attempted = true
            this._phase = 'binary'
            this._low = this._position + 1
            this._high = len(this._lines) - 1
            this._PrepareProbe()
          else
            this._position += 1
          endif
        else
          if stridx(line, PLAIN_HEADER) == 0
            this.plain_header = this._position
          endif
          this._position += 1
        endif
      else
        if this._position > this._high
          this._high = this._middle - 1
          this._PrepareProbe()
          continue
        endif
        const line = this._lines[this._position]
        if stridx(line, PLAIN_HEADER) == 0
          this.plain_header = this._position
          this._phase = 'done'
        else
          const key = EntryKey(line)
          if key ==# ''
            this._position += 1
          else
            # ASCII abbreviations ending in a letter are plain entries.
            if key =~# '[^ -~][a-z]$'
              this._low = this._position + 1
            else
              this._high = this._middle - 1
            endif
            this._PrepareProbe()
          endif
        endif
      endif
      inspected += 1
    endwhile
    return this._phase ==# 'done'
  enddef
endclass

# A resumable prefix lookup. Each step examines at most max_rows physical rows
# (including comments and malformed rows), or fallback entries.
export class PrefixSearch
  const _lines: list<string>
  const _prefix: string
  const _encoding: string
  const _okuri_start: number
  const _plain_start: number
  const _fallback: list<dictionary.Entry>
  var _phase: string = 'binary'
  var _section: number = 0
  var _low: number = 0
  var _high: number = -1
  var _middle: number = 0
  var _probe: number = 0
  var _position: number = 0

  def new(lines: list<string>, prefix: string, encoding: string,
      okuri_start: number, plain_start: number, sectioned: bool,
      fallback: dict<dictionary.Entry>)
    this._lines = lines
    this._prefix = prefix
    this._encoding = encoding
    this._okuri_start = okuri_start
    this._plain_start = plain_start
    this._fallback = sectioned ? [] : values(fallback)
    if sectioned
      this._StartSection()
    else
      this._phase = 'fallback'
    endif
  enddef

  def _StartSection()
    this._low = this._section == 0 ? this._okuri_start : this._plain_start
    this._high = this._section == 0 ? this._plain_start - 2 : len(this._lines) - 1
    this._phase = 'binary'
    this._PrepareProbe()
  enddef

  def _PrepareProbe()
    if this._low > this._high
      this._phase = 'scan'
      this._position = this._low
    else
      this._middle = (this._low + this._high) / 2
      this._probe = this._middle
    endif
  enddef

  def _NextSection()
    this._section += 1
    if this._section >= 2
      this._phase = 'done'
    else
      this._StartSection()
    endif
  enddef

  def IsDone(): bool
    return this._phase ==# 'done'
  enddef

  def Step(max_rows: number): list<dictionary.Entry>
    if max_rows <= 0
      throw 'caskk: prefix search step must be positive'
    endif
    final found: list<dictionary.Entry> = []
    var work = 0
    while work < max_rows && !this.IsDone()
      work += 1
      if this._phase ==# 'fallback'
        if this._position >= len(this._fallback)
          this._phase = 'done'
          continue
        endif
        const entry = this._fallback[this._position]
        this._position += 1
        if stridx(entry.lookup_key, this._prefix) == 0
          found->add(entry)
        endif
      elseif this._phase ==# 'binary'
        if this._probe > this._high
          this._high = this._middle - 1
          this._PrepareProbe()
          continue
        endif
        const key = EntryKey(this._lines[this._probe])
        if key ==# ''
          this._probe += 1
          continue
        endif
        const comparison = stridx(key, this._prefix) == 0 ? 0
          : CompareKeys(key, this._prefix, this._encoding)
        if this._section == 0 ? comparison > 0 : comparison < 0
          this._low = this._probe + 1
        else
          this._high = this._middle - 1
        endif
        this._PrepareProbe()
      else
        const end = this._section == 0 ? this._plain_start - 2 : len(this._lines) - 1
        if this._position > end
          this._NextSection()
          continue
        endif
        const line = this._lines[this._position]
        this._position += 1
        const key = EntryKey(line)
        if key ==# ''
          continue
        elseif stridx(key, this._prefix) != 0
          this._NextSection()
          continue
        endif
        try
          const entry = parser.ParseLine(line)
          if entry isnot null_object
            found->add(entry)
          endif
        catch
          # Unsupported rows do not hide later matching entries.
        endtry
      endif
    endwhile
    return found
  enddef
endclass

export class SourceData
  const _lines: list<string>
  # The plain header closes okuri; the retained line count closes plain.
  const _okuri_start: number
  const _plain_start: number
  const _sectioned: bool
  const _fallback: dict<dictionary.Entry>
  const _encoding: string

  # Builder has already resolved sections and parsed any fallback entries.
  def new(lines: list<string>, okuri_start: number, plain_start: number,
      sectioned: bool, fallback: dict<dictionary.Entry>, encoding: string)
    this._lines = lines
    this._okuri_start = okuri_start
    this._plain_start = plain_start
    this._sectioned = sectioned
    this._fallback = fallback
    this._encoding = encoding
  enddef

  def BeginPrefix(prefix: string): PrefixSearch
    return PrefixSearch.new(this._lines, prefix, this._encoding,
      this._okuri_start, this._plain_start, this._sectioned, this._fallback)
  enddef

  # Empty keys are rows excluded from the sorted sequence. Walk across them
  # when finding a midpoint or collecting adjacent duplicate keys.
  def _NextEntry(position: number, limit: number, direction: number): number
    var current = position
    while (direction > 0 ? current <= limit : current >= limit)
        && EntryKey(this._lines[current]) ==# ''
      current += direction
    endwhile
    return current
  enddef

  def _ParseMatches(key: string, low: number, high: number): list<dictionary.Entry>
    final entries: list<dictionary.Entry> = []
    for position in range(low, high)
      if EntryKey(this._lines[position]) !=# key
        continue
      endif
      try
        const entry = parser.ParseLine(this._lines[position])
        if entry isnot null_object
          entries->add(entry)
        endif
      catch
        # An invalid row with this key does not hide a valid duplicate row.
      endtry
    endfor
    return entries
  enddef

  # Synchronous consumers use the same bounded iterator as background completion.
  def Prefix(prefix: string): list<dictionary.Entry>
    const search = this.BeginPrefix(prefix)
    final found: list<dictionary.Entry> = []
    while !search.IsDone()
      found->extend(search.Step(64))
    endwhile
    return found
  enddef

  def Lookup(key: string, has_okuri: bool): list<dictionary.Entry>
    if !this._sectioned
      return has_key(this._fallback, key) ? [this._fallback[key]] : []
    endif
    const start = has_okuri ? this._okuri_start : this._plain_start
    const end = has_okuri ? this._plain_start - 2 : len(this._lines) - 1
    const descending = has_okuri
    var low = start
    var high = end
    while low <= high
      const midpoint = (low + high) / 2
      const middle = this._NextEntry(midpoint, high, 1)
      if middle > high
        high = midpoint - 1
        continue
      endif
      const middle_key = EntryKey(this._lines[middle])
      const comparison = CompareKeys(middle_key, key, this._encoding)
      if comparison == 0
        var first = middle
        var last = middle
        var previous = this._NextEntry(first - 1, start, -1)
        while previous >= start && EntryKey(this._lines[previous]) ==# key
          first = previous
          previous = this._NextEntry(first - 1, start, -1)
        endwhile
        var following = this._NextEntry(last + 1, end, 1)
        while following <= end && EntryKey(this._lines[following]) ==# key
          last = following
          following = this._NextEntry(last + 1, end, 1)
        endwhile
        return this._ParseMatches(key, first, last)
      elseif (descending && comparison > 0) || (!descending && comparison < 0)
        low = middle + 1
      else
        # Rows between midpoint and middle have no key.
        high = midpoint - 1
      endif
    endwhile
    return []
  enddef
endclass

# Incremental indexing work. Each Step inspects or parses at most max_lines
# physical rows, allowing callers to schedule the next slice with a timer.
export class Builder
  const _lines: list<string>
  const _encoding: string
  var _position: number = 0
  const _sections: SectionSearch
  var _phase: string = 'scan'
  var _okuri_header: number = -1
  var _plain_header: number = -1
  var _fallback: dict<dictionary.Entry> = {}
  var _result: SourceData = null_object

  def new(lines: list<string>, encoding: string = 'utf-8')
    this._lines = lines
    this._encoding = encoding
    this._sections = SectionSearch.new(lines)
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
      this._Finish()
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
    const sectioned = this._okuri_header >= 0 && this._plain_header > this._okuri_header
    this._result = SourceData.new(this._lines, this._okuri_header + 1, this._plain_header + 1,
      sectioned, this._fallback, this._encoding)
    this._phase = 'done'
  enddef

  def Step(max_lines: number): bool
    if max_lines <= 0
      throw 'caskk: dictionary index step must be positive'
    endif
    if this.IsDone()
      return true
    endif
    if this._phase ==# 'scan'
      if this._sections.Step(max_lines)
        this._okuri_header = this._sections.okuri_header
        this._plain_header = this._sections.plain_header
        this._FinishScan()
      endif
      return this.IsDone()
    endif
    var processed = 0
    while processed < max_lines
      if this._phase ==# 'fallback'
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

  def BeginPrefix(prefix: string): list<PrefixSearch>
    return mapnew(this._sources, (_, source) => source.BeginPrefix(prefix))
  enddef

  def Prefix(prefix: string): dict<dictionary.Entry>
    if prefix == ''
      return {}
    endif
    final sources: list<list<dictionary.Entry>> = []
    for source in this._sources
      sources->add(source.Prefix(prefix))
    endfor
    return merger.Merge(sources)
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

  # Retain source boundaries when combining different lookup keys.
  def LookupSources(queries: list<dictionary.Query>): list<dict<dictionary.Entry>>
    final result: list<dict<dictionary.Entry>> = []
    for source in this._sources
      final entries: list<dictionary.Entry> = []
      for query in queries
        entries->extend(source.Lookup(query.lookup_key, query.exact_okuri !=# ''))
      endfor
      result->add(merger.Merge([entries]))
    endfor
    return result
  enddef

  def IsReady(): bool
    return this._ready
  enddef

  def ResetForLoading()
    this._sources = []
    this._ready = false
  enddef

  def ReplacePartialWith(database: Database)
    this._sources = copy(database._sources)
    this._ready = false
  enddef

  def MarkReady()
    this._ready = true
  enddef

  def SourceCount(): number
    return len(this._sources)
  enddef

  def ReplaceWith(database: Database)
    this._sources = copy(database._sources)
    this._ready = true
  enddef
endclass

export def SourceFromLines(lines: list<string>, encoding: string = 'utf-8'): SourceData
  const builder = Builder.new(lines, encoding)
  while !builder.Step(max([1, len(lines)]))
  endwhile
  return builder.Result()
enddef
