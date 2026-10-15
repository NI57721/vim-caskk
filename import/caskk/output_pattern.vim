vim9script

export class OutputPattern
  # Decoded ordinary output, with the latent marker removed.
  const text: string
  # Character offset in text, or -1 when no latent marker is present.
  const boundary: number

  def new(this.text, this.boundary)
  enddef
endclass
