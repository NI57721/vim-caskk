vim9script

import 'caskk/dictionary.vim' as dictionary

# Sources are in configuration order; entries and candidates retain file order.
# Build new entries so shared, immutable source candidates are never modified.
export def Merge(sources: list<list<dictionary.Entry>>): dict<dictionary.Entry>
  final plain: dict<dict<bool>> = {}
  final order: dict<list<string>> = {}
  final annotations: dict<dict<list<string>>> = {}
  for source in sources
    for entry in source
      const key = entry.lookup_key
      if !has_key(order, key)
        plain[key] = {}
        order[key] = []
        annotations[key] = {}
      endif
      for candidate in entry.candidates
        plain[key][candidate.text] = get(plain[key], candidate.text, false) || candidate.has_plain_source
        if !has_key(annotations[key], candidate.text)
          order[key]->add(candidate.text)
          annotations[key][candidate.text] = []
        endif
        for annotation in candidate.annotations
          if index(annotations[key][candidate.text], annotation) == -1
            annotations[key][candidate.text]->add(annotation)
          endif
        endfor
      endfor
    endfor
  endfor

  final merged: dict<dictionary.Entry> = {}
  for [key, texts] in items(order)
    final candidates: list<dictionary.Candidate> = []
    for text in texts
      candidates->add(dictionary.Candidate.new(text, annotations[key][text], plain[key][text] ? 1 : 0))
    endfor
    merged[key] = dictionary.Entry.new(key, candidates)
  endfor
  return merged
enddef
