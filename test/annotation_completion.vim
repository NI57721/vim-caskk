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

suite.selection_wraps_and_prefix_changes_reset_focus = (): void => {
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
