vim9script
import 'caskk/verb_tags.vim' as tags
import 'caskk/dictionary.vim' as dictionary
import autoload 'caskk/dictionary/adjective.vim' as adjective
import autoload 'caskk/dictionary/verb.vim' as verb

export class Item
  const word: string
  const description: string
  def new(this.word, this.description)
  enddef
endclass

def Describe(tag: string): string
  if tag == '@adj'
    return '形容詞'
  endif
  const ichidan = {'@verb-1': '一段', '@verb-1-kureru': '一段（呉れる）', '@verb-1-uru': '一段（得る）'}
  if has_key(ichidan, tag)
    return ichidan[tag]
  endif
  var name = substitute(tag, '^@verb-', '', '')
  name = substitute(name, '^bungo-', '文語 ', '')
  name = substitute(name, '2-kami-', '上二段 ', '')
  name = substitute(name, '2-shimo-', '下二段 ', '')
  name = substitute(name, '\<5-', '五段 ', '')
  name = substitute(name, '\<4-', '四段 ', '')
  name = substitute(name, 'henkaku-', '変格 ', '')
  const rows = {a: 'ア行', k: 'カ行', g: 'ガ行', s: 'サ行', z: 'ザ行', t: 'タ行',
    d: 'ダ行', n: 'ナ行', h: 'ハ行', b: 'バ行', m: 'マ行', r: 'ラ行', y: 'ヤ行', w: 'ワ行'}
  final parts = split(name, ' ')
  const ending = split(parts[-1], '-')
  parts[-1] = get(rows, ending[0], ending[0])
  if len(ending) > 1
    const variants = {iku: '行く', yuku: '往く', aru: 'ある', tou: '問う',
      u: 'う', hu: 'ふ', zu: 'ず', du: 'づ'}
    parts[-1] ..= '（' .. get(variants, ending[1], ending[1]) .. '）'
  endif
  return join(parts, '')
enddef

# Match literal characters in order, allowing gaps without regex semantics.
def MatchesInOrder(word: string, query: string): bool
  var remaining = word
  for character in split(query, '\zs')
    const position = stridx(remaining, character)
    if position < 0
      return false
    endif
    remaining = strpart(remaining, position + strlen(character))
  endfor
  return true
enddef

def Priority(tag: string, okuri: string, reading: string): number
  const candidate = dictionary.Candidate.new('', [tag])
  const compatible = tag ==# '@adj' ? adjective.AllowsOkuri(candidate, okuri)
    : verb.AllowsOkuri(candidate, okuri)
  if !compatible
    return 3
  endif
  if tag ==# '@verb-1' && reading !=# ''
      && reading !~# '[いきぎしじちぢにひびぴみりゐえけげせぜてでねへべぺめれゑ]$'
    return 3
  endif
  if tag =~# '^@verb-bungo-'
    return 2
  endif
  if tag =~# '^@verb-\%(1-\|henkaku-\|5-.-\)'
    return 1
  endif
  return 0
enddef

export def Matches(prefix: string, okuri: string = '', reading: string = ''): list<Item>
  final groups: list<list<Item>> = [[], [], [], []]
  for tag in ['@adj'] + sort(keys(tags.ENDINGS))
    if MatchesInOrder(tag, prefix)
      const priority = okuri ==# '' ? 0 : Priority(tag, okuri, reading)
      groups[priority]->add(Item.new(tag, Describe(tag)))
    endif
  endfor
  return groups[0] + groups[1] + groups[2] + groups[3]
enddef

export class Completion
  var active: bool = false
  var prefix: string = ''
  var selected: number = 0
  var items: list<Item> = []
  def new()
  enddef
  def SetActive(value: bool)
    this.active = value
  enddef
  def Update(prefix: string, okuri: string = '', reading: string = '')
    this.prefix = prefix
    this.items = Matches(prefix, okuri, reading)
    this.selected = 0
  enddef
  def Move(delta: number)
    if !empty(this.items)
      this.selected = (this.selected + this.items->len() + delta) % this.items->len()
    endif
  enddef
  def SelectedLine(): number
    return empty(this.items) ? 0 : this.selected - max([0, this.selected - 3]) + 1
  enddef
  def Lines(): list<string>
    final lines: list<string> = []
    const first = max([0, this.selected - 3])
    for index in range(first, min([len(this.items) - 1, first + 5]))
      lines->add(this.items[index].word
        .. ' — ' .. this.items[index].description)
    endfor
    return lines
  enddef
endclass
