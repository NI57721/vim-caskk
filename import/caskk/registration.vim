vim9script

# Stable metadata for the UI, independent of mutable candidate selection.
export class Request
  const reading: string
  const okuri: string
  const exact_okuri: string
  const lookup_key: string

  def new(this.reading, this.okuri, this.exact_okuri, this.lookup_key)
  enddef
endclass
