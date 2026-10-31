vim9script

# Semantic output shared by composition and IME state management.
export class Result
  const start_conversion: bool
  const reading: string
  const okuri: string
  # An active boundary may precede an empty okuri, e.g. the pattern 'か*'.
  const okuri_started: bool

  def new(this.start_conversion, this.reading, this.okuri, this.okuri_started)
  enddef
endclass
