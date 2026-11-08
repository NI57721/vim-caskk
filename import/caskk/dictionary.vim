vim9script

import 'caskk/verb_tags.vim' as tags

export class Candidate
  const text: string
  const annotations: list<string>
  const has_plain_source: bool

  def new(this.text, annotations: list<string>, plain_source: number = -1)
    this.annotations = copy(annotations)
    this.has_plain_source = plain_source < 0 ? !tags.HasVerb(annotations) : plain_source != 0
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
