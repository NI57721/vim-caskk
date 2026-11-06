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

# Recent history is intentionally in-memory and bounded. Newer records are
# searched first so duplicate surface strings resolve to the latest reading.
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

  def Find(text: string): Record
    var best: Record = null_object
    for record in this._records
      if stridx(text, record.text) != 0
        continue
      endif
      if best is null_object || strchars(record.text) > strchars(best.text)
        best = record
      endif
    endfor
    return best
  enddef
endclass
