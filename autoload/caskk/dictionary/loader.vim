vim9script

import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/parser.vim' as parser
import autoload 'caskk/dictionary/merge.vim' as merger

export class Source
  const path: string
  const encoding: string = 'utf-8'

  def new(this.path, this.encoding = v:none)
  enddef
endclass

def ReadSource(source: Source): list<dictionary.Entry>
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

  final entries: list<dictionary.Entry> = []
  for index in range(len(lines))
    var line = lines[index]
    if line =~ '\r$'
      line = strpart(line, 0, strlen(line) - 1)
    endif
    var entry: dictionary.Entry
    try
      entry = parser.ParseLine(line)
    catch
      throw 'caskk: dictionary ' .. source.path .. ':' .. (index + 1) .. ': ' .. v:exception
    endtry
    if entry isnot null_object
      entries->add(entry)
    endif
  endfor
  return entries
enddef

# Eagerly read all configured sources in order. Returned data needs no file I/O.
export def Load(sources: list<Source>): dict<dictionary.Entry>
  final entries: list<list<dictionary.Entry>> = []
  for source in sources
    entries->add(ReadSource(source))
  endfor
  return merger.Merge(entries)
enddef
