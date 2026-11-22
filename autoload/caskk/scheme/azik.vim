vim9script

# QWERTY AZIK, based on Kiyoshi Kimura's original conversion tables.
# https://web.archive.org/web/20241217165614/http://hp.vector.co.jp/authors/VA002116/azik/azikinfo.htm
export def Definition(): dict<dict<string>>
  return {
    consonants: {
      k: 'k', s: 's', t: 't', n: 'n', h: 'h', f: 'f',
      m: 'm', y: 'y', r: 'r', w: 'w', g: 'g', z: 'z',
      d: 'd', b: 'b', p: 'p', v: 'v',
      ky: 'ky', kg: 'ky', sy: 'sy', x: 'sy', ty: 'ty', c: 'ty',
      ny: 'ny', ng: 'ny', hy: 'hy', hg: 'hy', my: 'my', mg: 'my',
      ry: 'ry', gy: 'gy', zy: 'zy', j: 'zy', by: 'by', py: 'py', pg: 'py',
      tg: 'th', dc: 'dh', ws: 'wh',
      l: 'x', ly: 'xy', lw: 'xw', q: 'N', ';': 'T',
    },
    combinations: {
      a: 'a', i: 'i', u: 'u', e: 'e', o: 'o',
      z: 'a*N', n: 'a*N', k: 'i*N', j: 'u*N', d: 'e*N', l: 'o*N',
      q: 'a*i', h: 'u*u', w: 'e*i', p: 'o*u',
    },
    specials: {
      '-': 'ー', ':': 'ー', nn: 'ん',
      tgu: 'とぅ', tgj: 'とぅ*ん', tgh: 'とぅ*う',
      dcu: 'どぅ', dcj: 'どぅ*ん', dch: 'どぅ*う',
      wp: 'うぉー', wl: 'うぉ*ん', fp: 'ふぉー',
      kf: 'き', jf: 'じゅ', hf: 'ふ', yf: 'ゆ', mf: 'む',
      nf: 'ぬ', df: 'で', cf: 'ちぇ', pf: 'ぽん',
      wf: 'わい', sf: 'さい', ss: 'せい',
      zc: 'ざ', zv: 'ざい', zf: 'ぜ', zx: 'ぜい',
      kt: 'こと', st: 'した', tt: 'たち', ht: 'ひと',
      wt: 'わた', mn: 'もの', ms: 'ます', ds: 'です',
      km: 'かも', tm: 'ため', dm: 'でも', kr: 'から',
      sr: 'する', tr: 'たら', nr: 'なる', yr: 'よる',
      rr: 'られ', zr: 'ざる', mt: 'また', tb: 'たび',
      nb: 'ねば', bt: 'びと', gr: 'がら', gt: 'ごと',
      nt: 'にち', dt: 'だち', wr: 'われ',
    },
  }
enddef
