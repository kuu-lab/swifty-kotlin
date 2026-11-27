import ParserProofs.Runtime.BalancedGroups

set_option warningAsError true

namespace TypeArguments.FFI

def declarationAnnotationEndOfHead (input : Input) (opening : Nat) : Nat :=
  let name := annotationName input (opening + 1)
  endOfAnnotationTypeArguments input (endOfAnnotationName input name)

def scanDeclarationAnnotation (input : Input) (opening : Nat) : GroupResult :=
  if (input.get opening).kind != .at then ⟨.missingOpen, opening⟩
  else
    let afterHead := declarationAnnotationEndOfHead input opening
    match (input.get afterHead).kind with
    | .openParen => scanAnnotationArguments input afterHead
    | .eof => ⟨.eof, afterHead⟩
    | _ => ⟨.closed, afterHead⟩

theorem declarationAnnotationLeavesEOFAtHeadEnd
    (atSign : (input.get opening).kind = .at)
    (eof : (input.get (declarationAnnotationEndOfHead input opening)).kind = .eof) :
    scanDeclarationAnnotation input opening = ⟨.eof, declarationAnnotationEndOfHead input opening⟩ := by
  simp [scanDeclarationAnnotation, atSign, eof]

theorem declarationAnnotationStopsAtHeadEndWithoutArguments
    (atSign : (input.get opening).kind = .at)
    (notArgs : (input.get (declarationAnnotationEndOfHead input opening)).kind ≠ .openParen) :
    (scanDeclarationAnnotation input opening).endIndex = declarationAnnotationEndOfHead input opening := by
  generalize kindEq : (input.get (declarationAnnotationEndOfHead input opening)).kind = kind at notArgs ⊢
  cases kind <;> simp_all [scanDeclarationAnnotation]

theorem annotationArgumentIncompleteAtEOFOrBoundary
    (result : scanAnnotationPrefix input ⟨index, .args stack⟩ fuel = .incomplete stop) :
    (input.get stop).kind = .eof ∨ annotationArgumentBoundary input stop = true := by
  induction fuel generalizing index stack with
  | zero => simp [scanAnnotationPrefix, annotationNextCharge] at result
  | succ fuel ih =>
    by_cases eof : (input.get index).kind = .eof
    · simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep, eof] at result
      subst stop
      exact .inl eof
    · by_cases recovery : annotationArgsAtRecoveryBoundary input index stack = true
      · have boundary := recovery
        rw [annotationArgsRecoveryRequiresOuterLevel] at boundary
        simp only [Bool.and_eq_true] at boundary
        simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep, eof, recovery] at result
        subst stop
        exact .inr boundary.2
      · cases next : groupStackStep stack (input.get index).kind with
        | nil =>
          cases fuel <;>
            simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep, eof, recovery, next] at result
        | cons head tail =>
          apply ih (index := index + 1) (stack := head :: tail)
          simpa [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep, eof, recovery, next] using result

theorem annotationArgumentsRecoveryEndsAtBoundary
    (result : scanAnnotationArguments input opening = ⟨.recovery, stop⟩) :
    annotationArgumentBoundary input stop = true := by
  unfold scanAnnotationArguments at result
  split at result
  · cases result
  · dsimp only at result
    split at result
    · cases result
    · rename_i index scanned
      split at result
      · cases result
      · rename_i notEOF
        have boundary := annotationArgumentIncompleteAtEOFOrBoundary scanned
        cases result
        exact boundary.resolve_left (by simpa only [beq_iff_eq] using notEOF)
    · cases result

theorem declarationAnnotationRecoveryEndsAtBoundary
    (result : scanDeclarationAnnotation input opening = ⟨.recovery, stop⟩) :
    annotationArgumentBoundary input stop = true := by
  unfold scanDeclarationAnnotation at result
  split at result
  · cases result
  · dsimp only at result
    split at result
    · exact annotationArgumentsRecoveryEndsAtBoundary result
    · cases result
    · cases result

inductive LeadingPrefixMode where
  | declaration
  | annotations
  | receiver

def LeadingPrefixMode.allowsModifiers : LeadingPrefixMode → Bool
  | .declaration => true
  | _ => false

def LeadingPrefixMode.allowsAnnotation (input : Input) (index : Nat) : LeadingPrefixMode → Bool
  | .receiver =>
    (input.get (index + 1)).receiverUseSiteTarget && (input.get (index + 2)).kind == .colon
  | _ => true

def isLeadingPrefix (input : Input) (mode : LeadingPrefixMode) (index : Nat) : Bool :=
  match (input.get index).kind with
  | .at => mode.allowsAnnotation input index
  | .modifier => mode.allowsModifiers
  | _ => false

def leadingPrefixStep (input : Input) (mode : LeadingPrefixMode) (index : Nat) :
    GroupResult ⊕ Nat :=
  let kind := (input.get index).kind
  if !isLeadingPrefix input mode index then
    .inl ⟨if kind == .eof then .eof else .closed, index⟩
  else if kind == .modifier then .inr (index + 1)
  else
    let annotation := scanDeclarationAnnotation input index
    match annotation.stop with
    | .recovery => .inl annotation
    | _ => if index < annotation.endIndex then .inr annotation.endIndex else .inl annotation

theorem leadingPrefixStepMovesForward
    (step : leadingPrefixStep input mode index = .inr nextIndex) :
    index < nextIndex := by
  unfold leadingPrefixStep at step
  dsimp only at step
  split at step
  · cases step
  · split at step
    · cases step
      exact Nat.lt_succ_self _
    · split at step <;> try cases step
      all_goals
        split at step
        · cases step
          assumption
        · cases step

def scanLeadingPrefix (input : Input) (mode : LeadingPrefixMode) (index : Nat) : Nat → GroupResult
  | 0 => ⟨.eof, index⟩
  | fuel + 1 =>
    match leadingPrefixStep input mode index with
    | .inl result => result
    | .inr next => scanLeadingPrefix input mode next fuel

inductive LeadingPrefixPath (input : Input) (mode : LeadingPrefixMode) : Nat → Nat → Nat → Prop where
  | empty : LeadingPrefixPath input mode index index 0
  | next (step : leadingPrefixStep input mode index = .inr nextIndex)
      (rest : LeadingPrefixPath input mode nextIndex last steps) :
      LeadingPrefixPath input mode index last (steps + 1)

theorem scanLeadingPrefixThroughPath (path : LeadingPrefixPath input mode index last steps) :
    scanLeadingPrefix input mode index (steps + fuel) = scanLeadingPrefix input mode last fuel := by
  induction path with
  | empty => simp
  | @next index nextIndex last steps step rest ih =>
    simpa [Nat.add_right_comm steps 1 fuel, scanLeadingPrefix, step] using ih

theorem scanLeadingPrefixStopsAtFirstNonPrefix
    (path : LeadingPrefixPath input mode index last steps)
    (notPrefix : isLeadingPrefix input mode last = false)
    (notEOF : (input.get last).kind ≠ .eof) :
    scanLeadingPrefix input mode index (steps + (fuel + 1)) = ⟨.closed, last⟩ := by
  rw [scanLeadingPrefixThroughPath path]
  simp [scanLeadingPrefix, leadingPrefixStep, notPrefix, notEOF]

theorem scanLeadingPrefixLeavesEOF
    (path : LeadingPrefixPath input mode index last steps)
    (eof : (input.get last).kind = .eof) :
    scanLeadingPrefix input mode index (steps + (fuel + 1)) = ⟨.eof, last⟩ := by
  rw [scanLeadingPrefixThroughPath path]
  simp [scanLeadingPrefix, leadingPrefixStep, isLeadingPrefix, eof]

theorem annotationArgumentBoundaryIsNotLeadingPrefix
    (boundary : annotationArgumentBoundary input index = true) :
    isLeadingPrefix input mode index = false := by
  generalize kindEq : (input.get index).kind = kind at boundary ⊢
  cases kind <;> simp_all [annotationArgumentBoundary, isLeadingPrefix]

theorem scanLeadingPrefixLeavesFollowingDeclaration
    (path : LeadingPrefixPath input mode index last steps)
    (atSign : (input.get last).kind = .at)
    (allowed : mode.allowsAnnotation input last = true)
    (recovered : scanDeclarationAnnotation input last = ⟨.recovery, boundary⟩) :
    scanLeadingPrefix input mode index (steps + (fuel + 1)) = ⟨.recovery, boundary⟩ ∧
      isLeadingPrefix input mode boundary = false := by
  rw [scanLeadingPrefixThroughPath path]
  exact ⟨by simp [scanLeadingPrefix, leadingPrefixStep, isLeadingPrefix, atSign, allowed, recovered],
    annotationArgumentBoundaryIsNotLeadingPrefix (declarationAnnotationRecoveryEndsAtBoundary recovered)⟩

inductive AccessorParameterStep where
  | eof
  | closed
  | advance (depth : Nat)

def accessorParameterStep (kind : Kind) (depth : Nat) : AccessorParameterStep :=
  match kind with
  | .eof => .eof
  | .openParen => .advance (depth + 1)
  | .closeParen => if depth == 1 then .closed else .advance (depth - 1)
  | _ => .advance depth

def accessorParameterEnd (input : Input) (index depth : Nat) : Nat → Option Nat
  | 0 => none
  | work + 1 =>
    match accessorParameterStep (input.get index).kind depth with
    | .eof => none
    | .closed => some (index + 1)
    | .advance next => accessorParameterEnd input (index + 1) next work

inductive AccessorParameterPath (input : Input) : Nat → Nat → Nat → Nat → Prop where
  | empty : AccessorParameterPath input index depth 0 depth
  | next (step : accessorParameterStep (input.get index).kind depth = .advance nextDepth)
      (rest : AccessorParameterPath input (index + 1) nextDepth steps lastDepth) :
      AccessorParameterPath input index depth (steps + 1) lastDepth

theorem accessorParameterEndThroughPath (path : AccessorParameterPath input index depth steps lastDepth) :
    accessorParameterEnd input index depth (steps + work) =
      accessorParameterEnd input (index + steps) lastDepth work := by
  induction path with
  | empty => simp
  | @next index depth nextDepth steps lastDepth step rest ih =>
    simpa [Nat.add_right_comm steps 1 work, Nat.add_right_comm index 1 steps,
      accessorParameterEnd, step] using ih

theorem accessorParameterEndAtMatchingClose
    (path : AccessorParameterPath input index depth steps 1)
    (close : (input.get (index + steps)).kind = .closeParen) :
    accessorParameterEnd input index depth (steps + (work + 1)) = some (index + steps + 1) := by
  rw [accessorParameterEndThroughPath path]
  simp [accessorParameterEnd, accessorParameterStep, close]

def isAccessorKeyword (token : LexToken) : Bool :=
  token.kind != .eof && (token.getterKeyword || token.setterKeyword)

def accessorHeaderBlockedByPredecessor (token : LexToken) : Bool :=
  match token.kind with
  | .dot | .questionDot | .doubleColon | .assign | .comma | .openParen | .openBrace | .openBracket => true
  | _ => token.keyword

def isAccessorHeaderFollower (kind : Kind) : Bool :=
  kind == .assign || kind == .openBrace || kind == .colon

def propertyTailAccessorAt (input : Input) (index : Nat) : Bool :=
  isAccessorKeyword (input.get index) &&
    !(index > 0 && accessorHeaderBlockedByPredecessor (input.get (index - 1))) &&
    (index + 1 < input.count) && (input.get (index + 1)).kind == .openParen &&
    (accessorParameterEnd input (index + 2) 1 (input.count - (index + 2))).any (fun after =>
      after < input.count && isAccessorHeaderFollower (input.get after).kind)

def scanPropertyTailAccessors (input : Input) (index : Nat) : Nat → Bool
  | 0 => false
  | work + 1 =>
    propertyTailAccessorAt input index || scanPropertyTailAccessors input (index + 1) work

theorem accessorHeaderFollowerIff :
    isAccessorHeaderFollower kind = true ↔ kind = .assign ∨ kind = .openBrace ∨ kind = .colon := by
  simp [isAccessorHeaderFollower, or_assoc]

theorem propertyTailAccessorRejectsExpressionPredecessor
    (previous : 0 < index)
    (blocked : accessorHeaderBlockedByPredecessor (input.get (index - 1)) = true) :
    propertyTailAccessorAt input index = false := by
  simp [propertyTailAccessorAt, previous, blocked]

theorem propertyTailAccessorRejectsMemberCall
    (previous : 0 < index)
    (memberAccess : (input.get (index - 1)).kind = .dot ∨
      (input.get (index - 1)).kind = .questionDot ∨ (input.get (index - 1)).kind = .doubleColon) :
    propertyTailAccessorAt input index = false := by
  apply propertyTailAccessorRejectsExpressionPredecessor previous
  rcases memberAccess with kind | kind | kind <;> simp [accessorHeaderBlockedByPredecessor, kind]

theorem propertyTailAccessorAtIff
    (parameters : accessorParameterEnd input (index + 2) 1 (input.count - (index + 2)) = some after) :
    propertyTailAccessorAt input index = true ↔
      isAccessorKeyword (input.get index) = true ∧
      (index = 0 ∨ accessorHeaderBlockedByPredecessor (input.get (index - 1)) = false) ∧
      index + 1 < input.count ∧ (input.get (index + 1)).kind = .openParen ∧
      after < input.count ∧
      ((input.get after).kind = .assign ∨ (input.get after).kind = .openBrace ∨
        (input.get after).kind = .colon) := by
  cases index <;>
    simp [propertyTailAccessorAt, parameters, accessorHeaderFollowerIff, and_assoc]

theorem propertyTailAccessorRejectsUnclosedParameters
    (parameters : accessorParameterEnd input (index + 2) 1 (input.count - (index + 2)) = none) :
    propertyTailAccessorAt input index = false := by
  simp [propertyTailAccessorAt, parameters]

theorem scanPropertyTailAccessorsIff :
    scanPropertyTailAccessors input index work = true ↔
      ∃ candidate, index ≤ candidate ∧ candidate < index + work ∧ propertyTailAccessorAt input candidate = true := by
  induction work generalizing index with
  | zero =>
    simp [scanPropertyTailAccessors]
    intro candidate lower upper
    omega
  | succ work ih =>
    simp only [scanPropertyTailAccessors, Bool.or_eq_true, ih]
    constructor
    · rintro (accepted | ⟨candidate, lower, upper, accepted⟩)
      · exact ⟨index, Nat.le_refl _, by omega, accepted⟩
      · exact ⟨candidate, by omega, by omega, accepted⟩
    · rintro ⟨candidate, lower, upper, accepted⟩
      by_cases same : candidate = index
      · exact .inl (same ▸ accepted)
      · exact .inr ⟨candidate, by omega, by omega, accepted⟩

def explicitBackingFieldAt (input : Input) (index : Nat) : Bool :=
  (input.get index).fieldKeyword &&
    ((input.get (index + 1)).kind == .assign || (input.get (index + 1)).kind == .colon)

theorem explicitBackingFieldAtIff :
    explicitBackingFieldAt input index = true ↔
      (input.get index).fieldKeyword = true ∧
        ((input.get (index + 1)).kind = .assign ∨ (input.get (index + 1)).kind = .colon) := by
  simp [explicitBackingFieldAt]

def isAmbiguousDeclarationPrefix : Kind → Bool
  | .at | .context | .modifier => true
  | _ => false

theorem ambiguousDeclarationPrefixIff :
    isAmbiguousDeclarationPrefix kind = true ↔
      kind = .at ∨ kind = .context ∨ kind = .modifier := by
  cases kind <;> simp [isAmbiguousDeclarationPrefix]

def canStartInfixCallArgument (token : LexToken) : Bool :=
  token.softKeyword || match token.kind with
    | .identifier | .literal | .expressionKeyword | .objectKeyword | .modifier
    | .openParen | .openBrace | .openBracket | .minus | .plus | .bang | .doubleColon | .stringStart => true
    | _ => false

theorem infixCallArgumentStartIff :
    canStartInfixCallArgument token = true ↔
      token.softKeyword = true ∨ token.kind ∈
        [.identifier, .literal, .expressionKeyword, .objectKeyword, .modifier, .openParen,
          .openBrace, .openBracket, .minus, .plus, .bang, .doubleColon, .stringStart] := by
  cases kind : token.kind <;> simp [canStartInfixCallArgument, kind]

def isTrailingLambdaOperatorContinuation (input : Input) (index : Nat) : Bool :=
  let token := input.get index
  if token.newline then false
  else match token.kind with
    | .varianceIn | .bangBang => true
    | .bang =>
      let next := (input.get (index + 1)).kind
      next == .varianceIn || next == .isKeyword
    | .identifier => canStartInfixCallArgument (input.get (index + 1))
    | _ => false

theorem trailingLambdaOperatorRejectsLeadingNewline
    (newline : (input.get index).newline = true) :
    isTrailingLambdaOperatorContinuation input index = false := by
  simp [isTrailingLambdaOperatorContinuation, newline]

theorem trailingLambdaOperatorContinuationIff :
    isTrailingLambdaOperatorContinuation input index = true ↔
      (input.get index).newline = false ∧
        ((input.get index).kind = .varianceIn ∨ (input.get index).kind = .bangBang ∨
          ((input.get index).kind = .bang ∧
            ((input.get (index + 1)).kind = .varianceIn ∨ (input.get (index + 1)).kind = .isKeyword)) ∨
          ((input.get index).kind = .identifier ∧ canStartInfixCallArgument (input.get (index + 1)) = true)) := by
  cases newline : (input.get index).newline <;>
    cases kind : (input.get index).kind <;>
    simp [isTrailingLambdaOperatorContinuation, newline, kind]

end TypeArguments.FFI
