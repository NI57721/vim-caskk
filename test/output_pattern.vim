vim9script

import 'caskk/output_pattern.vim' as pattern_types
import autoload 'caskk/scheme/output_pattern.vim' as output_pattern

final suite = themis#suite('output pattern parser')
const assert = themis#helper('assert')

def AssertPattern(actual: pattern_types.OutputPattern, text: string, boundary: number)
  assert.equals(actual.text, text)
  assert.equals(actual.boundary, boundary)
enddef

suite.plain_text = (): void => {
  AssertPattern(output_pattern.Parse('ain'), 'ain', -1)
  AssertPattern(output_pattern.Parse(''), '', -1)
}

suite.latent_boundary = (): void => {
  AssertPattern(output_pattern.Parse('a*in'), 'ain', 1)
}

suite.boundary_at_edges = (): void => {
  AssertPattern(output_pattern.Parse('*in'), 'in', 0)
  AssertPattern(output_pattern.Parse('ain*'), 'ain', 3)
  AssertPattern(output_pattern.Parse('*'), '', 0)
}

suite.literal_star = (): void => {
  AssertPattern(output_pattern.Parse('a\*in'), 'a*in', -1)
  AssertPattern(output_pattern.Parse('\*\*'), '**', -1)
}

suite.literal_backslash = (): void => {
  AssertPattern(output_pattern.Parse('a\\in'), 'a\in', -1)
  AssertPattern(output_pattern.Parse('\\'), '\', -1)
}

suite.escaped_characters_and_boundary = (): void => {
  AssertPattern(output_pattern.Parse('a\**in\*'), 'a*in*', 2)
  AssertPattern(output_pattern.Parse('\\*in'), '\in', 1)
  AssertPattern(output_pattern.Parse('\\\*'), '\*', -1)
}

suite.unicode_boundary_uses_character_offset = (): void => {
  AssertPattern(output_pattern.Parse('た*べ'), 'たべ', 1)
}

suite.unspecified_backslashes_are_preserved = (): void => {
  AssertPattern(output_pattern.Parse('a\qin'), 'a\qin', -1)
  AssertPattern(output_pattern.Parse('a\'), 'a\', -1)
}

suite.multiple_boundaries_are_rejected = (): void => {
  for pattern in ['a*b*c', '**', '\**a*', '\\**']
    var caught = ''
    try
      output_pattern.Parse(pattern)
    catch
      caught = v:exception
    endtry
    assert.equals(caught, 'caskk: output pattern contains multiple latent okuri boundaries')
  endfor
}
