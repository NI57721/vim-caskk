vim9script

export class Candidate
  const text: string
  const annotations: list<string>

  def new(this.text, annotations: list<string>)
    this.annotations = copy(annotations)
  enddef
endclass

# Conversion input is distinct from the coarse key used by SKK dictionaries.
export class Query
  const reading: string
  # Identity for learning/pinning: only the first character of the full okuri.
  const exact_okuri: string
  const lookup_key: string

  def new(this.reading, this.exact_okuri, this.lookup_key)
  enddef
endclass

# A source entry retains the SKK lookup key, not an inferred reading or okuri.
export class Entry
  const lookup_key: string
  const candidates: list<Candidate>

  def new(this.lookup_key, candidates: list<Candidate>)
    this.candidates = copy(candidates)
  enddef
endclass
