vim9script
import autoload 'caskk/registration/annotations.vim' as annotations
import 'caskk/verb_tags.vim' as tags
const suite = themis#suite('annotation completion')
const assert = themis#helper('assert')
suite.catalog_covers_recognized_tags = (): void => {
  const all = annotations.Matches('@')
  assert.equals(len(all), len(tags.ENDINGS) + 1)
  assert.equals(all[0].word, '@adj')
  for item in all
    assert.equals(item.description != '', true)
  endfor
  assert.equals(mapnew(annotations.Matches('@verb-5-k'), (_, item) => item.word),
    ['@verb-5-k', '@verb-5-k-iku', '@verb-5-k-yuku'])
  assert.equals(annotations.Matches('@unknown'), [])
}

suite.selection_wraps_and_query_changes_reset_focus = (): void => {
  const model = annotations.Completion.new()
  model.Update('@verb-5-k')
  model.Move(-1)
  assert.equals(model.selected, 2)
  model.Move(1)
  assert.equals(model.selected, 0)
  model.Update('@unknown')
  model.Move(1)
  assert.equals(model.items, [])
  assert.equals(model.Lines(), [])
}

suite.fuzzy_matching_keeps_input_order_and_catalog_order = (): void => {
  const words = mapnew(annotations.Matches('@v5'), (_, item) => item.word)
  assert.equals(words, filter(sort(keys(tags.ENDINGS)), (_, word) => word =~# '^@verb-5-'))
  assert.equals(mapnew(annotations.Matches('@v5k'), (_, item) => item.word),
    ['@verb-5-k', '@verb-5-k-iku', '@verb-5-k-yuku'])
  assert.equals(annotations.Matches('@5v'), [])
  assert.equals(annotations.Matches('@vv5'), [])
  assert.equals(annotations.Matches('@v.5'), [])
  assert.equals(annotations.Matches('@V5'), [])
}

suite.w_row_tags_use_w_and_describe_their_variants = (): void => {
  const items = annotations.Matches('@verb-5-w')
  assert.equals(mapnew(items, (_, item) => item.word),
    ['@verb-5-w', '@verb-5-w-tou'])
  assert.equals(mapnew(items, (_, item) => item.description),
    ['五段ワ行', '五段ワ行（問う）'])
}


suite.refreshed_catalog_has_57_verb_tags_and_describes_new_forms = (): void => {
  assert.equals(len(tags.ENDINGS), 57)
  assert.equals(len(annotations.Matches('@')), 58)
  for [tag, description] in [['@verb-1', '一段'], ['@verb-1-kureru', '一段（呉れる）'],
      ['@verb-1-uru', '一段（得る）'], ['@verb-henkaku-k', '変格カ行'],
      ['@verb-bungo-4-k', '文語四段カ行'], ['@verb-bungo-2-kami-k', '文語上二段カ行'],
      ['@verb-bungo-2-shimo-w', '文語下二段ワ行'], ['@verb-bungo-henkaku-r', '文語変格ラ行']]
    const item = filter(annotations.Matches(tag), (_, candidate) => candidate.word == tag)
    assert.equals(len(item), 1, tag)
    assert.equals(item[0].description, description, tag)
  endfor
}

suite.okuri_ranking_prefers_regular_compatible_tags_over_exceptions_and_classical_tags = (): void => {
  const words = mapnew(annotations.Matches('@', 'る', 'ふが'), (_, item) => item.word)
  assert.equals(words[0], '@verb-5-r')
  assert.equals(index(words, '@verb-5-r') < index(words, '@verb-5-r-aru'), true)
  assert.equals(index(words, '@verb-5-r-aru') < index(words, '@verb-bungo-4-r'), true)
  assert.equals(index(words, '@verb-bungo-4-r') < index(words, '@verb-1'), true)
  assert.equals(annotations.Matches('@', 'る', 'き')[0].word, '@verb-1')
  assert.equals(mapnew(annotations.Matches('@v5k', 'か', 'か'), (_, item) => item.word),
    ['@verb-5-k', '@verb-5-k-iku', '@verb-5-k-yuku'])
}
