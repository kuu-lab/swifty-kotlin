import ParserProofs.Runtime.DeclarationPrefixes

set_option warningAsError true

namespace TypeArguments.FFI

def continuesExpressionAfterNewline : Kind → Bool
  | .elseKeyword | .asKeyword | .byKeyword
  | .plus | .minus | .star | .slash | .percent | .ampAmp | .barBar
  | .equalEqual | .bangEqual | .tripleEqual | .notTripleEqual | .lessOrEqual | .greaterOrEqual
  | .assign | .plusAssign | .minusAssign | .starAssign | .slashAssign | .percentAssign
  | .dotDot | .dotDotLt | .questionQuestion | .questionColon
  | .comma | .dot | .questionDot | .colon | .arrow | .doubleColon => true
  | _ => false

theorem continuesExpressionAfterNewlineIff :
    continuesExpressionAfterNewline kind = true ↔
      kind ∈ [.elseKeyword, .asKeyword, .byKeyword, .plus, .minus, .star, .slash, .percent,
        .ampAmp, .barBar, .equalEqual, .bangEqual, .tripleEqual, .notTripleEqual,
        .lessOrEqual, .greaterOrEqual, .assign, .plusAssign, .minusAssign, .starAssign,
        .slashAssign, .percentAssign, .dotDot, .dotDotLt, .questionQuestion, .questionColon,
        .comma, .dot, .questionDot, .colon, .arrow, .doubleColon] := by
  cases kind <;> simp [continuesExpressionAfterNewline]

def continuesExpressionBeforeNewline : Kind → Bool
  | .dot | .questionDot | .questionColon | .ampAmp | .barBar
  | .elseKeyword | .catchKeyword | .finallyKeyword | .asKeyword => true
  | _ => false

theorem continuesExpressionBeforeNewlineIff :
    continuesExpressionBeforeNewline kind = true ↔
      kind ∈ [.dot, .questionDot, .questionColon, .ampAmp, .barBar,
        .elseKeyword, .catchKeyword, .finallyKeyword, .asKeyword] := by
  cases kind <;> simp [continuesExpressionBeforeNewline]

@[export kswiftk_lean_parser_continues_before_newline]
def continuesBeforeNewlineFrom (kind : UInt8) : Bool :=
  continuesExpressionBeforeNewline (decodeKind kind)

def shouldSplitStatementOnNewline : Kind → Bool
  | .dot | .comma | .questionDot | .questionColon | .ampAmp | .barBar
  | .closeParen | .closeBracket | .asKeyword => false
  | _ => true

theorem doesNotSplitStatementOnNewlineIff :
    shouldSplitStatementOnNewline kind = false ↔
      kind ∈ [.dot, .comma, .questionDot, .questionColon, .ampAmp, .barBar,
        .closeParen, .closeBracket, .asKeyword] := by
  cases kind <;> simp [shouldSplitStatementOnNewline]

@[export kswiftk_lean_parser_should_split_on_newline]
def shouldSplitOnNewlineFrom (kind : UInt8) : Bool :=
  shouldSplitStatementOnNewline (decodeKind kind)

def shouldStopStatementBefore (inBlock newline : Bool) : Kind → Bool
  | .eof | .closeBrace => true
  | .at | .modifier | .declaration | .funKeyword | .objectKeyword
  | .enumKeyword | .importKeyword | .returnKeyword | .packageKeyword => !inBlock && newline
  | _ => false

theorem shouldStopStatementBeforeIff :
    shouldStopStatementBefore inBlock newline kind = true ↔
      kind = .eof ∨ kind = .closeBrace ∨
        (inBlock = false ∧ newline = true ∧
          kind ∈ [.at, .modifier, .declaration, .funKeyword, .objectKeyword,
            .enumKeyword, .importKeyword, .returnKeyword, .packageKeyword]) := by
  cases kind <;> simp [shouldStopStatementBefore]

theorem shouldStopStatementInBlockIff :
    shouldStopStatementBefore true newline kind = true ↔ kind = .eof ∨ kind = .closeBrace := by
  simp [shouldStopStatementBeforeIff]

@[export kswiftk_lean_parser_should_stop_statement]
def shouldStopStatementFrom (kind inBlock newline : UInt8) : Bool :=
  shouldStopStatementBefore (inBlock != 0) (newline != 0) (decodeKind kind)

def isSynchronizationPoint (inBlock newline : Bool) : Kind → Bool
  | .eof | .declaration | .funKeyword | .objectKeyword | .importKeyword | .packageKeyword => true
  | .closeBrace | .semicolon | .catchKeyword | .finallyKeyword | .elseKeyword => inBlock
  | _ => inBlock && newline

theorem synchronizationPointOutsideBlockIff :
    isSynchronizationPoint false newline kind = true ↔
      kind ∈ [.eof, .declaration, .funKeyword, .objectKeyword, .importKeyword, .packageKeyword] := by
  cases kind <;> simp [isSynchronizationPoint]

theorem synchronizationPointInsideBlockIff :
    isSynchronizationPoint true newline kind = true ↔
      newline = true ∨
        kind ∈ [.eof, .declaration, .funKeyword, .objectKeyword, .importKeyword, .packageKeyword,
          .closeBrace, .semicolon, .catchKeyword, .finallyKeyword, .elseKeyword] := by
  cases kind <;> simp [isSynchronizationPoint]

def synchronizationPointAt (input : Input) (inBlock : Bool) (index : Nat) : Bool :=
  let token := input.get index
  isSynchronizationPoint inBlock token.newline token.kind

def scanToStop (stopAt : Nat → Bool) (index : Nat) : Nat → Nat
  | 0 => index
  | remaining + 1 =>
    if stopAt index then index
    else scanToStop stopAt (index + 1) remaining

theorem scanToStopSpec (stopAt : Nat → Bool) (index remaining : Nat) :
    let stop := scanToStop stopAt index remaining
    index ≤ stop ∧ stop ≤ index + remaining ∧
      (∀ visited, index ≤ visited → visited < stop → stopAt visited = false) ∧
      (stop < index + remaining → stopAt stop = true) := by
  induction remaining generalizing index with
  | zero =>
    simp [scanToStop]
    intro visited lower upper
    omega
  | succ remaining ih =>
    cases hit : stopAt index with
    | true =>
      simp [scanToStop, hit]
      intro visited lower upper
      omega
    | false =>
      simp only [scanToStop, hit, Bool.false_eq_true, if_false]
      obtain ⟨lower, upper, skipped, stopped⟩ := ih (index + 1)
      refine ⟨by omega, by omega, ?_, ?_⟩
      · intro visited beginAt beforeStop
        by_cases atStart : visited = index
        · simpa [atStart] using hit
        · exact skipped visited (by omega) beforeStop
      · intro beforeEnd
        exact stopped (by omega)

theorem scanToStopStopsAtFirst
    (lower : index ≤ point) (upper : point ≤ index + remaining)
    (hit : stopAt point = true)
    (first : ∀ visited, index ≤ visited → visited < point → stopAt visited = false) :
    scanToStop stopAt index remaining = point := by
  obtain ⟨start, _, skipped, stopped⟩ := scanToStopSpec stopAt index remaining
  apply Nat.le_antisymm
  · apply Nat.le_of_not_gt
    intro past
    have impossible := skipped point lower past
    simp [hit] at impossible
  · apply Nat.le_of_not_gt
    intro before
    have sync := stopped (by omega)
    simp [first _ start before] at sync

def scanToSynchronizationPoint (input : Input) (inBlock : Bool) (index remaining : Nat) : Nat :=
  scanToStop (synchronizationPointAt input inBlock) index remaining

def skipToSynchronizationPoint (input : Input) (inBlock : Bool) (index : Nat) : Nat :=
  if index < input.count ∧ inBlock = false ∧ (input.get index).kind = .closeBrace then index + 1
  else scanToSynchronizationPoint input inBlock index (input.count - index)

theorem skipToSynchronizationPointUnexpectedCloseBrace
    (available : index < input.count) (brace : (input.get index).kind = .closeBrace) :
    skipToSynchronizationPoint input false index = index + 1 := by
  simp [skipToSynchronizationPoint, available, brace]

theorem scanToSynchronizationPointStopsAtFirst
    (lower : index ≤ point) (upper : point ≤ index + remaining)
    (hit : synchronizationPointAt input inBlock point = true)
    (first : ∀ visited, index ≤ visited → visited < point →
      synchronizationPointAt input inBlock visited = false) :
    scanToSynchronizationPoint input inBlock index remaining = point :=
  scanToStopStopsAtFirst lower upper hit first

theorem skipToSynchronizationPointStopsAtFirst
    (ordinary : ¬(index < input.count ∧ inBlock = false ∧ (input.get index).kind = .closeBrace))
    (lower : index ≤ point) (upper : point ≤ input.count)
    (hit : synchronizationPointAt input inBlock point = true)
    (first : ∀ visited, index ≤ visited → visited < point →
      synchronizationPointAt input inBlock visited = false) :
    skipToSynchronizationPoint input inBlock index = point := by
  rw [skipToSynchronizationPoint, if_neg ordinary]
  exact scanToSynchronizationPointStopsAtFirst lower (by omega) hit first

theorem scanToSynchronizationPointDoesNotConsumeEOF
    (lower : index ≤ eof) (terminal : (input.get eof).kind = .eof) :
    scanToSynchronizationPoint input inBlock index remaining ≤ eof := by
  obtain ⟨_, _, skipped, _⟩ := scanToStopSpec (synchronizationPointAt input inBlock) index remaining
  apply Nat.le_of_not_gt
  intro past
  simpa [synchronizationPointAt, terminal, isSynchronizationPoint] using skipped eof lower past

theorem skipToSynchronizationPointDoesNotConsumeEOF
    (lower : index ≤ eof) (terminal : (input.get eof).kind = .eof) :
    skipToSynchronizationPoint input inBlock index ≤ eof := by
  unfold skipToSynchronizationPoint
  split
  · next exception =>
    have different : index ≠ eof := by
      intro atEOF
      simp [atEOF, terminal] at exception
    omega
  · exact scanToSynchronizationPointDoesNotConsumeEOF lower terminal

structure TopLevelRecoveryPlan where
  skippedEnd : Nat
  forceAdvance : Bool

def TopLevelRecoveryPlan.endIndex (plan : TopLevelRecoveryPlan) : Nat :=
  plan.skippedEnd + if plan.forceAdvance then 1 else 0

def topLevelRecoveryAt (input : Input) (start : Nat) : TopLevelRecoveryPlan :=
  let skippedEnd := skipToSynchronizationPoint input false start
  ⟨skippedEnd, decide (skippedEnd = start ∧ start < input.count ∧ (input.get start).kind ≠ .eof)⟩

def topLevelStatementRecovery (input : Input) (before after : Nat) : Option TopLevelRecoveryPlan :=
  if before = after then some (topLevelRecoveryAt input after) else none

theorem topLevelRecoveryOnlyWhenNoProgress :
    topLevelStatementRecovery input before after = none ↔ before ≠ after := by
  by_cases same : before = after <;> simp [topLevelStatementRecovery, same]

theorem topLevelRecoveryUsesSynchronization (same : before = after) :
    (topLevelStatementRecovery input before after).map TopLevelRecoveryPlan.skippedEnd =
      some (skipToSynchronizationPoint input false after) := by
  simp [topLevelStatementRecovery, same, topLevelRecoveryAt]

theorem topLevelRecoveryForcesAdvanceIff :
    (topLevelRecoveryAt input start).forceAdvance = true ↔
      skipToSynchronizationPoint input false start = start ∧
        start < input.count ∧ (input.get start).kind ≠ .eof := by
  simp [topLevelRecoveryAt]

theorem topLevelRecoveryForcesExactlyOne
    (stalled : skipToSynchronizationPoint input false start = start)
    (available : start < input.count) (notEOF : (input.get start).kind ≠ .eof) :
    (topLevelRecoveryAt input start).endIndex = start + 1 := by
  simp [TopLevelRecoveryPlan.endIndex, topLevelRecoveryAt, stalled, available, notEOF]

theorem topLevelRecoveryDoesNotConsumeEOF
    (lower : start ≤ eof) (terminal : (input.get eof).kind = .eof) :
    (topLevelRecoveryAt input start).endIndex ≤ eof := by
  unfold TopLevelRecoveryPlan.endIndex
  change skipToSynchronizationPoint input false start +
    (if (topLevelRecoveryAt input start).forceAdvance = true then 1 else 0) ≤ eof
  split
  · next force =>
    have ⟨stalled, _, notEOF⟩ := topLevelRecoveryForcesAdvanceIff.mp force
    have different : start ≠ eof := by
      intro same
      exact notEOF (same ▸ terminal)
    omega
  · simpa using skipToSynchronizationPointDoesNotConsumeEOF (inBlock := false) lower terminal

def qualifiedPathCanConsume
    (input : Input) (allowWildcard stopAtAs : Bool) (start index : Nat) : Bool :=
  let token := input.get index
  token.kind != .eof &&
    (!shouldStopStatementBefore false token.newline token.kind ||
      (token.identifierLike && (input.get (index + 1)).kind == .at)) &&
    (index == start || !token.newline) &&
    !(stopAtAs && token.kind == .asKeyword) &&
    (token.kind == .dot || token.identifierLike || (allowWildcard && token.kind == .star))

theorem qualifiedPathCanConsumeIff :
    qualifiedPathCanConsume input allowWildcard stopAtAs start index = true ↔
      let token := input.get index
      token.kind ≠ .eof ∧
        (shouldStopStatementBefore false token.newline token.kind = false ∨
          (token.identifierLike = true ∧ (input.get (index + 1)).kind = .at)) ∧
        (index = start ∨ token.newline = false) ∧
        (stopAtAs = false ∨ token.kind ≠ .asKeyword) ∧
        (token.kind = .dot ∨ token.identifierLike = true ∨
          (allowWildcard = true ∧ token.kind = .star)) := by
  cases stopAtAs <;> simp [qualifiedPathCanConsume, and_assoc, or_assoc]

theorem qualifiedPathWildcardIff
    (star : (input.get index).kind = .star) (notName : (input.get index).identifierLike = false) :
    qualifiedPathCanConsume input allowWildcard stopAtAs start index = true ↔
      allowWildcard = true ∧ (index = start ∨ (input.get index).newline = false) := by
  simp [qualifiedPathCanConsumeIff, star, notName, shouldStopStatementBefore, and_comm]

theorem qualifiedPathStopsAtAs (asToken : (input.get index).kind = .asKeyword) :
    qualifiedPathCanConsume input allowWildcard true start index = false := by
  simp [qualifiedPathCanConsume, asToken]

theorem qualifiedPathRejectsAs (asToken : (input.get index).kind = .asKeyword)
    (notName : (input.get index).identifierLike = false) :
    qualifiedPathCanConsume input allowWildcard stopAtAs start index = false := by
  simp [qualifiedPathCanConsume, asToken, notName]

def qualifiedPathEnd (input : Input) (allowWildcard stopAtAs : Bool) (start : Nat) : Nat :=
  scanToStop (fun index => !qualifiedPathCanConsume input allowWildcard stopAtAs start index)
    start (input.count - start)

theorem qualifiedPathStopsAtFirst
    (lower : start ≤ point) (upper : point ≤ input.count)
    (stop : qualifiedPathCanConsume input allowWildcard stopAtAs start point = false)
    (first : ∀ visited, start ≤ visited → visited < point →
      qualifiedPathCanConsume input allowWildcard stopAtAs start visited = true) :
    qualifiedPathEnd input allowWildcard stopAtAs start = point := by
  unfold qualifiedPathEnd
  apply scanToStopStopsAtFirst lower (by omega)
  · simp [stop]
  · intro visited beginAt beforeStop
    simp [first visited beginAt beforeStop]

theorem qualifiedPathDoesNotConsumeEOF
    (lower : start ≤ eof) (terminal : (input.get eof).kind = .eof) :
    qualifiedPathEnd input allowWildcard stopAtAs start ≤ eof := by
  unfold qualifiedPathEnd
  obtain ⟨_, _, skipped, _⟩ := scanToStopSpec
    (fun index => !qualifiedPathCanConsume input allowWildcard stopAtAs start index)
    start (input.count - start)
  apply Nat.le_of_not_gt
  intro past
  simpa [qualifiedPathCanConsume, terminal] using skipped eof lower past

def headerAliasLength (input : Input) (allowAlias : Bool) (start : Nat) : Nat :=
  if allowAlias = true ∧ (input.get start).kind = .asKeyword then
    let name := input.get (start + 1)
    if name.kind ≠ .eof ∧ name.identifierLike = true then 2 else 1
  else 0

def headerHasTerminator (input : Input) (index : Nat) : Bool :=
  (input.get index).kind == .semicolon

def headerTailEnd (input : Input) (allowAlias : Bool) (start : Nat) : Nat :=
  start + headerAliasLength input allowAlias start +
    (if headerHasTerminator input (start + headerAliasLength input allowAlias start) then 1 else 0)

theorem headerAliasPresentIff :
    headerAliasLength input allowAlias start = 2 ↔
      allowAlias = true ∧ (input.get start).kind = .asKeyword ∧
        (input.get (start + 1)).kind ≠ .eof ∧ (input.get (start + 1)).identifierLike = true := by
  by_cases alias : allowAlias = true ∧ (input.get start).kind = .asKeyword <;>
    by_cases name : (input.get (start + 1)).kind ≠ .eof ∧ (input.get (start + 1)).identifierLike = true <;>
    simp [headerAliasLength, alias, name, ← and_assoc]

theorem headerAliasMissingIff :
    headerAliasLength input allowAlias start = 1 ↔
      allowAlias = true ∧ (input.get start).kind = .asKeyword ∧
        ((input.get (start + 1)).kind = .eof ∨ (input.get (start + 1)).identifierLike = false) := by
  by_cases alias : allowAlias = true ∧ (input.get start).kind = .asKeyword <;>
    by_cases eof : (input.get (start + 1)).kind = .eof <;>
    cases name : (input.get (start + 1)).identifierLike <;>
    simp [headerAliasLength, alias, eof, name, ← and_assoc]

theorem headerTailConsumesTerminatorIff :
    headerTailEnd input allowAlias start = start + headerAliasLength input allowAlias start + 1 ↔
      (input.get (start + headerAliasLength input allowAlias start)).kind = .semicolon := by
  by_cases semicolon : (input.get (start + headerAliasLength input allowAlias start)).kind = .semicolon <;>
    simp [headerTailEnd, headerHasTerminator, semicolon]

theorem headerTailMissingAliasEnd (missing : headerAliasLength input allowAlias start = 1) :
    headerTailEnd input allowAlias start =
      if (input.get (start + 1)).kind = .semicolon then start + 2 else start + 1 := by
  by_cases semicolon : (input.get (start + 1)).kind = .semicolon <;>
    simp [headerTailEnd, headerHasTerminator, missing, semicolon, Nat.add_assoc]

theorem headerAliasDoesNotConsumeEOF
    (lower : start ≤ eof) (terminal : (input.get eof).kind = .eof) :
    start + headerAliasLength input allowAlias start ≤ eof := by
  unfold headerAliasLength
  split
  · next alias =>
    have afterAs : start < eof := by
      have different : eof ≠ start := by
        intro same
        subst eof
        simp [terminal] at alias
      omega
    dsimp only
    split
    · next name =>
      have different : eof ≠ start + 1 := by
        intro same
        rw [same] at terminal
        exact name.1 terminal
      omega
    · omega
  · simpa using lower

theorem headerTailDoesNotConsumeEOF
    (lower : start ≤ eof) (terminal : (input.get eof).kind = .eof) :
    headerTailEnd input allowAlias start ≤ eof := by
  have aliasBound := headerAliasDoesNotConsumeEOF (allowAlias := allowAlias) lower terminal
  by_cases atTerminator : start + headerAliasLength input allowAlias start = eof
  · simp [headerTailEnd, headerHasTerminator, atTerminator, terminal]
  · unfold headerTailEnd
    split <;> omega

def headerKeywordKind (isImport : Bool) : Kind :=
  if isImport then .importKeyword else .packageKeyword

def headerKeywordEnd (input : Input) (isImport : Bool) (start : Nat) : Nat :=
  if (input.get start).kind == headerKeywordKind isImport then start + 1 else start

structure HeaderPlan where
  pathStart : Nat
  pathEnd : Nat
  aliasLength : Nat
  hasTerminator : Bool

def HeaderPlan.endIndex (plan : HeaderPlan) : Nat :=
  plan.pathEnd + plan.aliasLength + (if plan.hasTerminator then 1 else 0)

def scanHeaderDeclaration (input : Input) (isImport : Bool) (start : Nat) : HeaderPlan :=
  let pathStart := headerKeywordEnd input isImport start
  let pathEnd := qualifiedPathEnd input isImport isImport pathStart
  let aliasLength := headerAliasLength input isImport pathEnd
  ⟨pathStart, pathEnd, aliasLength, headerHasTerminator input (pathEnd + aliasLength)⟩

theorem headerDeclarationMissingKeywordIff :
    (scanHeaderDeclaration input isImport start).pathStart = start ↔
      (input.get start).kind ≠ headerKeywordKind isImport := by
  by_cases keyword : (input.get start).kind = headerKeywordKind isImport <;>
    simp [scanHeaderDeclaration, headerKeywordEnd, keyword]

theorem qualifiedPathEndAtStartIff :
    qualifiedPathEnd input allowWildcard stopAtAs start = start ↔
      input.count ≤ start ∨ qualifiedPathCanConsume input allowWildcard stopAtAs start start = false := by
  cases fuel : input.count - start with
  | zero =>
    have exhausted : input.count ≤ start := by omega
    simp [qualifiedPathEnd, fuel, scanToStop, exhausted]
  | succ remaining =>
    have available : ¬ input.count ≤ start := by omega
    cases accepts : qualifiedPathCanConsume input allowWildcard stopAtAs start start with
    | false => simp [qualifiedPathEnd, fuel, scanToStop, accepts]
    | true =>
      have bounds := (scanToStopSpec
        (fun index => !qualifiedPathCanConsume input allowWildcard stopAtAs start index)
        (start + 1) remaining).1
      simp [qualifiedPathEnd, fuel, scanToStop, accepts, available]
      omega

theorem headerDeclarationMissingPathIff :
    let plan := scanHeaderDeclaration input isImport start
    plan.pathEnd = plan.pathStart ↔
      input.count ≤ plan.pathStart ∨
        qualifiedPathCanConsume input isImport isImport plan.pathStart plan.pathStart = false :=
  qualifiedPathEndAtStartIff

theorem headerDeclarationMissingPathRecoversAtPathStart
    (missing : (scanHeaderDeclaration input isImport start).pathEnd =
      (scanHeaderDeclaration input isImport start).pathStart) :
    (scanHeaderDeclaration input isImport start).endIndex =
      headerTailEnd input isImport (scanHeaderDeclaration input isImport start).pathStart := by
  have tail : (scanHeaderDeclaration input isImport start).endIndex =
      headerTailEnd input isImport (scanHeaderDeclaration input isImport start).pathEnd := rfl
  rw [tail, missing]

theorem headerKeywordDoesNotConsumeEOF
    (lower : start ≤ eof) (terminal : (input.get eof).kind = .eof) :
    headerKeywordEnd input isImport start ≤ eof := by
  unfold headerKeywordEnd
  split
  · next keyword =>
    have different : start ≠ eof := by
      intro same
      subst eof
      cases isImport <;> simp [headerKeywordKind, terminal] at keyword
    omega
  · exact lower

theorem headerDeclarationDoesNotConsumeEOF
    (lower : start ≤ eof) (terminal : (input.get eof).kind = .eof) :
    (scanHeaderDeclaration input isImport start).endIndex ≤ eof := by
  exact headerTailDoesNotConsumeEOF
    (qualifiedPathDoesNotConsumeEOF (headerKeywordDoesNotConsumeEOF lower terminal) terminal) terminal

def HeaderPlan.encode (plan : HeaderPlan) (start : Nat) : Nat :=
  (plan.pathEnd - plan.pathStart) * 16 + plan.aliasLength * 4 +
    (if plan.hasTerminator then 2 else 0) + (if plan.pathStart > start then 1 else 0)

end TypeArguments.FFI
