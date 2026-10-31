vim9script

import 'caskk/dictionary.vim' as dictionary

# Candidates come from the merged, text-deduplicated sources.
# MRU is supplied newest first for one reading + exact-okuri identity.
export def Rank(candidates: list<dictionary.Candidate>, pinned: string = '', mru: list<string> = [], demoted: list<string> = []): list<dictionary.Candidate>
  final preferred: list<dictionary.Candidate> = []
  final normal: list<dictionary.Candidate> = []
  final deferred: list<dictionary.Candidate> = []
  final normal_by_text: dict<dictionary.Candidate> = {}
  for candidate in candidates
    if candidate.text ==# pinned
      preferred->add(candidate)
    elseif index(demoted, candidate.text) >= 0
      deferred->add(candidate)
    else
      normal->add(candidate)
      normal_by_text[candidate.text] = candidate
    endif
  endfor

  final ranked: list<dictionary.Candidate> = copy(preferred)
  final learned: dict<bool> = {}
  for text in mru
    if has_key(normal_by_text, text) && !has_key(learned, text)
      ranked->add(normal_by_text[text])
      learned[text] = true
    endif
  endfor
  for candidate in normal
    if !has_key(learned, candidate.text)
      ranked->add(candidate)
    endif
  endfor
  return ranked + deferred
enddef
