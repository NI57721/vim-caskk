vim9script

import 'caskk/input.vim' as input
import 'caskk/dictionary.vim' as dictionary
import 'caskk/composition.vim' as composition
import autoload 'caskk/conversion.vim' as conversion
import autoload 'caskk/completion.vim' as completion
import autoload 'caskk/dictionary/lookup.vim' as lookup
import autoload 'caskk/dictionary/index.vim' as dict_index
import autoload 'caskk/user_state.vim' as user_state
import autoload 'caskk/input/normalize.vim' as normalize
import autoload 'caskk/composer.vim' as composer
import autoload 'caskk/scheme.vim' as scheme
import autoload 'caskk/state.vim' as state_types
import autoload 'caskk/input/mode.vim' as input_mode

# One ordered output and the state immediately after it.
# Text is Direct output, committed text, or replacement text for Preedit.
# commit_preedit closes the existing range rather than inserting a second copy.
# replace_preedit replaces that range; it may also commit the replacement.
# The state snapshot retains the original reading even during candidate display.
# Unhandled named keys and controls are returned to the Vim integration layer.
export class Result
  const text: string
  const unhandled: list<input.Event>
  const state: state_types.Snapshot
  const commit_preedit: bool = false
  const in_candidate: bool = false
  const replace_preedit: bool = false
  const registration_requested: bool = false
  const pending_display: bool = false
  const preedit_text: string = ''
  const dictionary_loading: bool = false

  def new(this.text, this.unhandled, this.state, this.commit_preedit = v:none,
      this.in_candidate = v:none, this.replace_preedit = v:none,
      this.registration_requested = v:none, this.pending_display = v:none,
      this.preedit_text = v:none, this.dictionary_loading = v:none)
  enddef
endclass

# Connect core input stages without depending on Vim buffers or presentation.
export class Session
  const _normalizer: normalize.Normalizer
  const _composer: composer.Composer
  const _state: state_types.State
  const _entries: dict<dictionary.Entry>
  const _dictionary_index: dict_index.Database
  const _preferences: user_state.State
  const _small_tsu_okuri_as_t: bool
  const _register_mode_conversions: bool
  var _completions: list<completion.Candidate> = []
  var _completion_index: number = 0
  var _prepared: conversion.Candidates = null_object
  var _selection: conversion.Selection = null_object
  var _request_preferences: user_state.State = null_object
  var _reading_after_cancel: bool = false
  var _direct_input_continuation: bool = false
  var _input_mode: string = input_mode.HIRAGANA
  var _abbreviation_return_mode: string = ''

  def new(compiled: scheme.CompiledScheme, sticky_key: string = '',
      entries: dict<dictionary.Entry> = {}, preferences: user_state.State = null_object,
      initial_reading: string = '', small_tsu_okuri_as_t: bool = true, keyboard_layout: string = '',
      keyboard_layout_overrides: dict<string> = {}, input_mode_name: string = input_mode.HIRAGANA,
      register_mode_conversions: bool = true, dictionary_index: dict_index.Database = null_object,
      initial_okuri: string = '')
    this._normalizer = normalize.Normalizer.new(sticky_key, keyboard_layout, keyboard_layout_overrides)
    this._composer = composer.Composer.new(compiled)
    this._state = state_types.State.new()
    this._entries = copy(entries)
    this._dictionary_index = dictionary_index
    this._preferences = preferences is null_object ? user_state.State.new() : preferences
    this._small_tsu_okuri_as_t = small_tsu_okuri_as_t
    this._register_mode_conversions = register_mode_conversions
    if !input_mode.IsValid(input_mode_name)
      throw 'caskk: unknown input mode: ' .. input_mode_name
    endif
    this._input_mode = input_mode_name
    if initial_reading != ''
      this._state.Apply(composition.Result.new(true, initial_reading, initial_okuri, initial_okuri != ''))
    endif
  enddef

  def _PrepareConversion(entries: dict<dictionary.Entry>, preferences: user_state.State): Result
    this._reading_after_cancel = false
    this._prepared = conversion.Prepare(entries, preferences, this._state.reading, this._state.okuri,
      this._small_tsu_okuri_as_t, this._dictionary_index)
    this._request_preferences = preferences
    if empty(this._prepared.candidates)
      if this._dictionary_index isnot null_object && !this._dictionary_index.IsReady()
        this._prepared = null_object
        return Result.new('', [], this._state.GetSnapshot(), false, false, false, false, false,
          this._DisplayPreedit(), true)
      endif
      return Result.new('', [], this._state.GetSnapshot(), false, false, false, true, false,
        this._DisplayPreedit())
    endif
    this._selection = conversion.Selection.new(this._prepared, preferences)
    return Result.new(this._Render(this._selection.CurrentText()), [], this._state.GetSnapshot(),
      false, true, true, false, false, this._DisplayPreedit())
  enddef

  def _Render(text: string): string
    return input_mode.Render(text, this._input_mode)
  enddef

  def _DisplayPreedit(): string
    return this._Render(this._state.reading .. this._state.okuri)
  enddef

  def _ApplyOutput(composed: composition.Result, auto_convert: bool): Result
    const text = this._state.Apply(composed)
    if auto_convert && this._state.in_preedit && this._state.okuri_started && this._state.okuri != ''
      return this._PrepareConversion(this._entries, this._preferences)
    endif
    const snapshot = this._state.GetSnapshot()
    return Result.new(snapshot.in_preedit ? '' : this._Render(text), [], snapshot, false, false,
      false, false, false, snapshot.in_preedit ? this._DisplayPreedit() : '')
  enddef

  def _FeedAbbreviation(key: string): Result
    const code = char2nr(key)
    if strchars(key) != 1 || code < 0x20 || (code >= 0x7f && code <= 0x9f)
      return Result.new('', [input.Event.new(key)], this._state.GetSnapshot())
    endif
    return this._ApplyOutput(composition.Result.new(true, key, '', false), false)
  enddef

  def _FeedFullwidthAlphanumeric(key: string): Result
    const code = char2nr(key)
    if strchars(key) != 1 || code < 0x20 || (code >= 0x7f && code <= 0x9f)
      return Result.new('', [input.Event.new(key)], this._state.GetSnapshot())
    endif
    return Result.new(this._Render(key), [], this._state.GetSnapshot())
  enddef

  def _Apply(matched_results: list<composer.Result>, auto_convert: bool = true): list<Result>
    final results: list<Result> = []
    for matched in matched_results
      if this.InCandidate()
        results->extend(this.Commit())
      endif
      var modified = false
      for event in matched.events
        modified = modified || event.modified
      endfor
      if modified
        this._direct_input_continuation = false
      elseif !this._state.in_preedit && matched.output isnot null_object
        this._direct_input_continuation = true
      endif
      if matched.output is null_object
        for event in matched.events
          const code = char2nr(event.key)
          if strchars(event.key) == 1 && code >= 0x20 && !(code >= 0x7f && code <= 0x9f)
            # A failed Modified combination falls back to the normalized key,
            # without starting Preedit or an okuri boundary on its own.
            results->add(this._ApplyOutput(composition.Result.new(false, event.key, '', false), auto_convert))
          else
            results->add(Result.new('', [event], this._state.GetSnapshot()))
          endif
        endfor
      else
        const standalone_vowel = matched.output.boundary == -1
          && index(['あ', 'い', 'う', 'え', 'お'], matched.output.text) >= 0
        # Standalone vowel combinations are kana; other combination-only keys
        # remain literal in Direct input instead of producing an isolated output.
        if !this._state.in_preedit && !matched.is_special && !matched.is_symbol
            && len(matched.events) == 1 && !standalone_vowel
            && !matched.events[0].modified
          results->add(this._ApplyOutput(composition.Result.new(false,
            matched.events[0].key, '', false), auto_convert))
          continue
        endif
        var composed = composer.Compose(matched, this._state.in_preedit)
        if this._direct_input_continuation && !this._state.in_preedit
          composed = composition.Result.new(false, composed.reading, composed.okuri,
            composed.okuri_started)
        endif
        results->add(this._ApplyOutput(composed, auto_convert))
      endif
    endfor
    return results
  enddef

  # Input is one physical KeyToken, already named by the integration layer.
  def Feed(key: string): list<Result>
    this.CancelCompletion()
    final results: list<Result> = []
    if this._input_mode == input_mode.FULLWIDTH_ALPHANUMERIC
      return [this._FeedFullwidthAlphanumeric(key)]
    endif
    if this._input_mode == input_mode.ABBREVIATION
      if this.InCandidate()
        results->extend(this.Commit())
        if this._input_mode != input_mode.ABBREVIATION
          results->extend(this.Feed(key))
          return results
        endif
      endif
      this._prepared = null_object
      results->add(this._FeedAbbreviation(key))
      return results
    endif
    if this.InCandidate() || (this._reading_after_cancel && this._state.okuri != '')
      results->extend(this.Commit())
    endif
    this._prepared = null_object
    if !this._state.in_preedit && empty(this._composer.Pending())
        && !this._normalizer.HasPendingModifier() && !this._composer.IsSpecialStart(key)
        && this._normalizer.IsShiftedSymbol(key)
      results->add(this._ApplyOutput(composition.Result.new(false, key, '', false), false))
      return results
    endif
    const input_events = this._composer.IsSpecialStart(key)
      ? this._normalizer.FeedSpecial(key) : this._normalizer.Feed(key)
    for event in input_events
      if event.modified
        this._direct_input_continuation = false
      endif
      results->extend(this._Apply(this._composer.Feed(event)))
    endfor
    return results
  enddef

  # Delete only unfinished input; reading and candidate editing are separate.
  def BackspacePending(): bool
    if this._normalizer.Backspace()
      return true
    endif
    const pending = this._composer.Pending()
    if empty(pending)
      return false
    endif
    this._composer.Backspace()
    if pending[-1].modified
      this._normalizer.RestoreModifier()
    endif
    return true
  enddef

  def BackspacePreedit(): Result
    this.CancelCompletion()
    if this.InCandidate() || !this._state.Backspace()
      return null_object
    endif
    const snapshot = this._state.GetSnapshot()
    const display = snapshot.in_preedit ? this._DisplayPreedit() : ''
    return Result.new(display, [], snapshot, !snapshot.in_preedit, false, true, false, false,
      display)
  enddef

  def Commit(): list<Result>
    if this.InCompletion()
      const chosen = this._completions[this._completion_index]
      const text = this._Render(chosen.text)
      if chosen.learnable
        this._preferences.Learn(chosen.query, chosen.candidate.text)
      endif
      this.CancelCompletion()
      this._state.Commit()
      this._normalizer.Reset()
      this._prepared = null_object
      this._direct_input_continuation = true
      this._reading_after_cancel = false
      this._RestoreAbbreviationMode()
      return [Result.new(text, [], this._state.GetSnapshot(), true, false, true)]
    endif
    this._reading_after_cancel = false
    if this.InCandidate()
      const text = this._Render(this._selection.Commit())
      this._state.Commit()
      this._normalizer.Reset()
      this._selection = null_object
      this._prepared = null_object
      this._direct_input_continuation = true
      this._RestoreAbbreviationMode()
      return [Result.new(text, [], this._state.GetSnapshot(), true)]
    endif
    this._prepared = null_object
    final results = this._Apply(this._composer.Flush(), false)
    this._normalizer.Reset()
    if this._state.in_preedit
      const text = this._Render(this._state.Commit())
      results->add(Result.new(text, [], this._state.GetSnapshot(), true))
      this._RestoreAbbreviationMode()
    endif
    return results
  enddef

  def InCompletion(): bool
    return !empty(this._completions)
  enddef

  def ShowCompletion(minimum: number): bool
    if this.InCompletion()
      this.MoveCompletion(1)
      return true
    endif
    if this.InCandidate() || !this._state.in_preedit || strchars(this._state.reading) < minimum
        || !empty(this._composer.Pending()) || this._normalizer.HasPendingModifier()
      return false
    endif
    this._completions = completion.Prepare(this._entries, this._preferences,
      this._state.reading, this._state.okuri, this._dictionary_index, this._small_tsu_okuri_as_t)
    this._completion_index = 0
    return this.InCompletion()
  enddef

  def MoveCompletion(delta: number)
    if !this.InCompletion()
      throw 'caskk: no active completion'
    endif
    const count = len(this._completions)
    this._completion_index = ((this._completion_index + delta) % count + count) % count
  enddef

  def CancelCompletion()
    this._completions = []
    this._completion_index = 0
  enddef

  def GetCompletionInfo(): conversion.CandidateListInfo
    if !this.InCompletion()
      return null_object
    endif
    final candidates: list<conversion.CandidateInfo> = []
    const count = len(this._completions)
    for index in range(count)
      const item = this._completions[index]
      const annotations = item.candidate.annotations + ['読み: ' .. item.query.reading
        .. (item.okuri == '' ? '' : '*' .. item.okuri)]
      candidates->add(conversion.CandidateInfo.new(index, count, this._Render(item.text),
        annotations, item.tier))
    endfor
    return conversion.CandidateListInfo.new(this._completion_index, candidates)
  enddef

  def InCandidate(): bool
    return this._selection isnot null_object && this._selection.IsActive()
  enddef

  def GetCandidateInfo(): conversion.CandidateInfo
    if !this.InCandidate()
      return null_object
    endif
    const info = this._selection.GetInfo()
    return conversion.CandidateInfo.new(info.index, info.count, this._Render(info.text), info.annotations, info.tier)
  enddef

  def GetCandidatesInfo(): conversion.CandidateListInfo
    if !this.InCandidate()
      return null_object
    endif
    const info = this._selection.GetCandidatesInfo()
    final candidates: list<conversion.CandidateInfo> = []
    for candidate in info.candidates
      candidates->add(conversion.CandidateInfo.new(candidate.index, candidate.count,
        this._Render(candidate.text), candidate.annotations, candidate.tier))
    endfor
    return conversion.CandidateListInfo.new(info.selected_index, candidates)
  enddef

  def TogglePin()
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    this._selection.TogglePin()
  enddef

  def ToggleDemote()
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    this._selection.ToggleDemote()
  enddef

  def CanDeleteUserEntry(): bool
    return this.InCandidate() && this._preferences.HasEntryForLookup(
      this._prepared.query, this._selection.CurrentCandidateText())
  enddef

  def DeleteUserEntry(): Result
    if !this.CanDeleteUserEntry()
      throw 'caskk: selected candidate is not a user entry'
    endif
    const info = this._selection.GetInfo()
    const candidate_text = this._selection.CurrentCandidateText()
    this._preferences.DeleteEntryForLookup(this._prepared.query, candidate_text)
    const prepared = conversion.Prepare(this._entries, this._preferences,
      this._prepared.query.reading, this._prepared.okuri, this._small_tsu_okuri_as_t,
      this._dictionary_index)
    this._prepared = prepared
    if empty(prepared.candidates)
      this._selection = null_object
      this._prepared = null_object
      return Result.new(this._DisplayPreedit(), [], this._state.GetSnapshot(), false, false, true,
        false, false, this._DisplayPreedit())
    endif
    this._selection = conversion.Selection.new(prepared, this._preferences)
    const texts = mapnew(prepared.candidates, (_, candidate) => candidate.text)
    const selected = index(texts, candidate_text)
    return this.SelectCandidate(selected >= 0 ? selected : min([info.index, len(texts) - 1]))
  enddef

  # A missing dictionary key leaves an empty set here for registration UI.
  # Otherwise no prepared request is represented by null_object.
  def GetCandidates(): conversion.Candidates
    return this._prepared
  enddef

  def StartConversion(entries: dict<dictionary.Entry>, preferences: user_state.State): list<Result>
    this.CancelCompletion()
    if this.InCandidate()
      throw 'caskk: conversion selection is active'
    endif
    this._prepared = null_object
    final results = this._Apply(this._composer.Flush(), false)
    this._normalizer.Reset()
    for result in results
      if !empty(result.unhandled)
        return results
      endif
    endfor
    if !this._state.in_preedit || this._state.reading == ''
      return results
    endif
    results->add(this._PrepareConversion(entries, preferences))
    return results
  enddef

  def SelectCandidate(index: number): Result
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    const text = this._Render(this._selection.Select(index))
    return Result.new(text, [], this._state.GetSnapshot(), false, true, true,
      false, false, this._DisplayPreedit())
  enddef

  # The separate registration UI supplies a candidate body without display okuri.
  def Register(candidate: dictionary.Candidate): Result
    if this._prepared is null_object || this.InCandidate()
      throw 'caskk: no current dictionary registration request'
    endif
    if candidate.text == ''
      throw 'caskk: registered candidate text must not be empty'
    endif
    const text = this._Render(candidate.text .. this._prepared.okuri)
    if candidate.text !=# this._prepared.query.reading
      this._request_preferences.AddEntry(this._prepared.query, candidate)
      this._request_preferences.Learn(this._prepared.query, candidate.text)
    endif
    this._state.Commit()
    this._normalizer.Reset()
    this._prepared = null_object
    this._request_preferences = null_object
    this._reading_after_cancel = false
    this._RestoreAbbreviationMode()
    return Result.new(text, [], this._state.GetSnapshot(), true, false, true)
  enddef

  def CancelRegistration(): Result
    if this._prepared is null_object || this.InCandidate()
      throw 'caskk: no current dictionary registration request'
    endif
    const text = this._Render(this._prepared.query.reading .. this._prepared.okuri)
    this._prepared = null_object
    this._request_preferences = null_object
    this._reading_after_cancel = true
    return Result.new(text, [], this._state.GetSnapshot(), false, false, true)
  enddef

  def CancelConversion(): Result
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    const text = this._Render(this._selection.Cancel())
    this._selection = null_object
    this._prepared = null_object
    this._reading_after_cancel = true
    return Result.new(text, [], this._state.GetSnapshot(), false, false, true,
      false, false, this._DisplayPreedit())
  enddef

  def PreviousCandidate(): Result
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    if this._selection.Previous()
      return Result.new(this._Render(this._selection.CurrentText()), [], this._state.GetSnapshot(),
        false, true, true, false, false, this._DisplayPreedit())
    endif
    return this.CancelConversion()
  enddef

  def NextCandidate(): Result
    if !this.InCandidate()
      throw 'caskk: no active conversion selection'
    endif
    if this._selection.Next()
      return Result.new(this._Render(this._selection.CurrentText()), [], this._state.GetSnapshot(),
        false, true, true, false, false, this._DisplayPreedit())
    endif
    # Exhaustion requests registration rather than committing or wrapping.
    # Keep the prepared query and full okuri for the separate registration UI.
    const text = this._Render(this._selection.Cancel())
    this._selection = null_object
    this._reading_after_cancel = false
    return Result.new(text, [], this._state.GetSnapshot(), false, false, true, true, false,
      this._DisplayPreedit())
  enddef

  def Pending(): list<input.Event>
    return this._composer.Pending()
  enddef

  def IsSpecialContinuation(key: string): bool
    return this._composer.IsSpecialContinuation(key)
  enddef

  def CanChangeInputMode(): bool
    return !this._state.in_preedit && !this.InCandidate() && !this.InCompletion() && empty(this._composer.Pending())
      && !this._normalizer.HasPendingModifier()
  enddef

  def SetInputMode(requested: string): bool
    if !this.CanChangeInputMode()
      return false
    endif
    const previous = this._input_mode
    const next = input_mode.Transition(previous, requested)
    if next == input_mode.ABBREVIATION && previous != input_mode.ABBREVIATION
      this._abbreviation_return_mode = previous
    elseif previous == input_mode.ABBREVIATION && next != input_mode.ABBREVIATION
      this._abbreviation_return_mode = ''
    endif
    this._input_mode = next
    return true
  enddef

  def CanCommitPreeditAsMode(requested: string): bool
    if !this._state.in_preedit || this.InCandidate() || this.InCompletion() || !empty(this._composer.Pending())
        || this._normalizer.HasPendingModifier()
      return false
    endif
    const next = input_mode.Transition(this._input_mode, requested)
    return (this._input_mode == input_mode.HIRAGANA
        && (next == input_mode.KATAKANA || next == input_mode.HALFWIDTH_KATAKANA))
      || (this._input_mode == input_mode.ABBREVIATION
        && next == input_mode.FULLWIDTH_ALPHANUMERIC)
  enddef

  def CommitPreeditAsMode(requested: string): list<Result>
    if !this.CanCommitPreeditAsMode(requested)
      throw 'caskk: preedit cannot be committed in the requested input mode'
    endif
    const snapshot = this._state.GetSnapshot()
    const previous_mode = this._input_mode
    const previous_abbreviation_return_mode = this._abbreviation_return_mode
    const output_mode = input_mode.Transition(this._input_mode, requested)
    this._input_mode = output_mode
    this._abbreviation_return_mode = ''
    try
      const results = this.Commit()
      if this._register_mode_conversions
        const query = lookup.CreateQuery(snapshot.reading, snapshot.okuri, this._small_tsu_okuri_as_t)
        const text = input_mode.Render(snapshot.reading, output_mode)
        if text !=# '' && text !=# snapshot.reading
          const candidate = dictionary.Candidate.new(text, [])
          this._preferences.AddEntry(query, candidate)
          this._preferences.Learn(query, text)
        endif
      endif
      return results
    finally
      this._input_mode = previous_mode
      this._abbreviation_return_mode = previous_abbreviation_return_mode
    endtry
  enddef

  def _RestoreAbbreviationMode()
    if this._input_mode == input_mode.ABBREVIATION
      this._input_mode = this._abbreviation_return_mode == '' ? input_mode.HIRAGANA
        : this._abbreviation_return_mode
      this._abbreviation_return_mode = ''
    endif
  enddef

  def GetInputMode(): string
    return this._input_mode
  enddef

  def HasPendingModifier(): bool
    return this._normalizer.HasPendingModifier()
  enddef

  def RenderText(text: string): string
    return this._Render(text)
  enddef

  def GetSnapshot(): state_types.Snapshot
    return this._state.GetSnapshot()
  enddef
endclass
