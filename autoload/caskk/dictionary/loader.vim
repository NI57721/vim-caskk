vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger
import autoload 'caskk/dictionary/index.vim' as index

export class Source
  const path: string
  const encoding: string = 'utf-8'

  def new(this.path, this.encoding = v:none)
  enddef
endclass

const READ_CHUNK_BYTES = 65536

class SourceReader
  const _source: Source
  const _file_size: number
  var _offset: number = 0
  var _pending: blob = 0z
  var _lines: list<string> = []
  var _done: bool = false

  def new(source: Source)
    this._source = source
    this._file_size = getfsize(source.path)
    if this._file_size < 0
      throw 'caskk: cannot read dictionary: ' .. source.path .. ': file not found'
    endif
  enddef

  def IsDone(): bool
    return this._done
  enddef

  def Lines(): list<string>
    if !this._done
      throw 'caskk: dictionary source is not fully read'
    endif
    return this._lines
  enddef

  def _Decode(bytes: blob, keep_final_empty: bool)
    if empty(bytes)
      return
    endif
    var decoded: list<string>
    try
      decoded = blob2str(bytes, {encoding: this._source.encoding})
    catch
      throw 'caskk: cannot decode dictionary: ' .. this._source.path .. ' (' .. this._source.encoding .. '): ' .. v:exception
    endtry
    if !keep_final_empty && !empty(decoded) && decoded[-1] ==# ''
      remove(decoded, -1)
    endif
    for line in decoded
      var normalized = line
      if empty(this._lines) && stridx(normalized, "\ufeff") == 0
        normalized = strpart(normalized, strlen("\ufeff"))
      endif
      if normalized =~ '\r$'
        normalized = strpart(normalized, 0, strlen(normalized) - 1)
      endif
      this._lines->add(normalized)
    endfor
  enddef

  def Step(): bool
    if this._done
      return true
    endif
    var chunk: blob
    try
      chunk = readblob(this._source.path, this._offset, READ_CHUNK_BYTES)
    catch
      throw 'caskk: cannot read dictionary: ' .. this._source.path .. ': ' .. v:exception
    endtry
    if empty(chunk) && this._offset < this._file_size
      throw 'caskk: cannot read dictionary: ' .. this._source.path .. ': file changed while loading'
    endif
    this._offset += len(chunk)
    const combined = this._pending + chunk
    var newline = -1
    for position in range(len(combined) - 1, 0, -1)
      if combined[position] == 0x0a
        newline = position
        break
      endif
    endfor
    if newline >= 0
      const has_more = this._offset < this._file_size || newline + 1 < len(combined)
      this._Decode(combined[0 : newline], !has_more)
      this._pending = newline + 1 < len(combined) ? combined[newline + 1 :] : 0z
    else
      this._pending = combined
    endif
    if this._offset >= this._file_size
      if !empty(this._pending)
        this._Decode(this._pending, true)
        this._pending = 0z
      endif
      this._done = true
    endif
    return this._done
  enddef
endclass

def ReadLines(source: Source): list<string>
  var bytes: blob
  try
    bytes = readblob(source.path)
  catch
    throw 'caskk: cannot read dictionary: ' .. source.path .. ': ' .. v:exception
  endtry

  var lines: list<string>
  try
    lines = blob2str(bytes, {encoding: source.encoding})
  catch
    throw 'caskk: cannot decode dictionary: ' .. source.path .. ' (' .. source.encoding .. '): ' .. v:exception
  endtry
  if !empty(lines) && stridx(lines[0], "\ufeff") == 0
    lines[0] = strpart(lines[0], strlen("\ufeff"))
  endif

  for line_number in range(len(lines))
    var line = lines[line_number]
    if line =~ '\r$'
      line = strpart(line, 0, strlen(line) - 1)
    endif
    lines[line_number] = line
  endfor
  return lines
enddef

def ReadSource(source: Source): list<dictionary.Entry>
  final entries: list<dictionary.Entry> = []
  for line in ReadLines(source)
    var entry: dictionary.Entry
    try
      entry = parser.ParseLine(line)
    catch
      # System dictionaries may contain entries outside the supported subset.
      # Ignore only that physical line and keep reading the rest of the source.
      continue
    endtry
    if entry isnot null_object
      entries->add(entry)
    endif
  endfor
  return entries
enddef

export def Open(sources: list<Source>): index.Database
  final indexed_sources: list<index.SourceData> = []
  for source in sources
    indexed_sources->add(index.SourceFromLines(ReadLines(source)))
  endfor
  return index.Database.new(indexed_sources)
enddef

# Read each source when it becomes active, then expose the index work in bounded
# slices. Decoding waits for line boundaries, preserving multibyte encodings.
export class DatabaseBuilder
  const _sources: list<Source>
  var _source_index: number = 0
  var _source_reader: SourceReader = null_object
  var _source_builder: index.Builder = null_object
  var _indexed_sources: list<index.SourceData> = []
  var _result: index.Database = null_object

  def new(sources: list<Source>)
    this._sources = copy(sources)
    if empty(sources)
      this._result = index.Database.new([])
    endif
  enddef

  def IsDone(): bool
    return this._result isnot null_object
  enddef

  def Result(): index.Database
    if !this.IsDone()
      throw 'caskk: dictionary loading is not complete'
    endif
    return this._result
  enddef

  def Step(max_lines: number): bool
    if max_lines <= 0
      throw 'caskk: dictionary load step must be positive'
    endif
    if this.IsDone()
      return true
    endif
    if this._source_builder is null_object
      if this._source_reader is null_object
        this._source_reader = SourceReader.new(this._sources[this._source_index])
      endif
      if !this._source_reader.Step()
        return false
      endif
      this._source_builder = index.Builder.new(this._source_reader.Lines())
      this._source_reader = null_object
    endif
    if this._source_builder.Step(max_lines)
      this._indexed_sources->add(this._source_builder.Result())
      this._source_builder = null_object
      this._source_index += 1
      if this._source_index >= len(this._sources)
        this._result = index.Database.new(this._indexed_sources)
      endif
    endif
    return this.IsDone()
  enddef
endclass

# Eagerly read all configured sources in order. Returned data needs no file I/O.
export def Load(sources: list<Source>): dict<dictionary.Entry>
  final entries: list<list<dictionary.Entry>> = []
  for source in sources
    entries->add(ReadSource(source))
  endfor
  return merger.Merge(entries)
enddef
