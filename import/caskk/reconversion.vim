vim9script

# A confirmed surface string and the reading metadata needed to look it up again.
export class Record
  const text: string
  const reading: string
  const okuri: string
  const exact_okuri: string

  def new(this.text, this.reading, this.okuri, this.exact_okuri)
  enddef
endclass

export class Match
  const record: Record
  const start_byte: number

  def new(this.record, this.start_byte)
  enddef
endclass

# Recent history is intentionally in-memory and bounded. Newer records are
# searched first so equal-length matches resolve to the latest record.
export class History
  const _limit: number
  var _records: list<Record> = []

  def new(limit: number = 32)
    if limit < 1
      throw 'caskk: reconversion history limit must be positive'
    endif
    this._limit = limit
  enddef

  def Add(text: string, reading: string, okuri: string = '', exact_okuri: string = '')
    if text ==# '' || reading ==# ''
      return
    endif
    this._records->insert(Record.new(text, reading, okuri, exact_okuri))
    if len(this._records) > this._limit
      remove(this._records, this._limit)
    endif
  enddef

  # cursor_byte and start_byte are zero-based offsets within the line.
  def Find(line_text: string, cursor_byte: number): Match
    var best: Match = null_object
    var best_length = 0
    for record in this._records
      const length = strchars(record.text)
      if length <= best_length
        continue
      endif
      const start_byte = strridx(line_text, record.text, cursor_byte)
      if start_byte >= 0 && cursor_byte < start_byte + strlen(record.text)
        best = Match.new(record, start_byte)
        best_length = length
      endif
    endfor
    return best
  enddef
endclass
