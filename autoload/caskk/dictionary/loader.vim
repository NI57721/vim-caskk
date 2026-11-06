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

  final normalized: list<string> = []
  for line_number in range(len(lines))
    var line = lines[line_number]
    if line =~ '\r$'
      line = strpart(line, 0, strlen(line) - 1)
    endif
    normalized->add(line)
  endfor
  return normalized
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

# Eagerly read all configured sources in order. Returned data needs no file I/O.
export def Load(sources: list<Source>): dict<dictionary.Entry>
  final entries: list<list<dictionary.Entry>> = []
  for source in sources
    entries->add(ReadSource(source))
  endfor
  return merger.Merge(entries)
enddef
