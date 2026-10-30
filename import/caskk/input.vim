vim9script

# Physical uppercase and sticky-key input are normalized before reaching core logic.
export class Event
  const key: string
  const modified: bool = false

  def new(this.key, this.modified = v:none)
  enddef
endclass
