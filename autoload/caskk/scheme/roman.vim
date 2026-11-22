vim9script

# Return fresh maps: customizing a scheme never changes the built-in definition.
export def Definition(): dict<dict<string>>
  final consonants = {
    k: 'k', g: 'g', s: 's', z: 'z', t: 't', d: 'd', n: 'n', h: 'h',
    b: 'b', p: 'p', m: 'm', y: 'y', r: 'r', w: 'w', f: 'f', v: 'v',
    j: 'zy', c: 'k', x: 'x', l: 'x',
    ky: 'ky', gy: 'gy', sy: 'sy', zy: 'zy', ty: 'ty', dy: 'dy', ny: 'ny',
    hy: 'hy', by: 'by', py: 'py', my: 'my', ry: 'ry',
    sh: 'sy', ch: 'ty', cy: 'ty', jy: 'zy', fy: 'fy',
    wh: 'wh', xy: 'xy', xw: 'xw', ly: 'xy', lw: 'xw', ts: 'ts', th: 'th', dh: 'dh',
  }
  for key in split('bcdfghjklmprstvwxyz', '\zs')
    consonants[key .. key] = 'T' .. consonants[key]
  endfor
  final specials = {
    nn: 'ん', "n'": 'ん',
    xtu: 'っ', xtsu: 'っ', ltu: 'っ', ltsu: 'っ',
    '!': '！', ',': '、', '-': 'ー', '.': '。', ':': '：', ';': '；', '?': '？', '[': '「', ']': '」',
  }
  return {consonants: consonants,
    combinations: {a: 'a', i: 'i', u: 'u', e: 'e', o: 'o'}, specials: specials}
enddef
