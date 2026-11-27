import ParserProofs.Runtime.TypeArgumentScans

set_option warningAsError true

namespace TypeArguments.FFI

structure ParameterState where
  prefixEnd : Option Nat := none
  angleDepth : Nat := 0
  inDefault : Bool := false
  prefixComplete : Bool := false
  atPending : Bool := false
  targetPending : Bool := false

def ParameterState.step (state : ParameterState) (input : Input) (index : Nat) (token : LexToken) :
    ParameterState :=
  if token.kind == .comma && state.angleDepth == 0 then {} else
    let updated := match token.kind with
      | .colon =>
        if state.angleDepth == 0 && !state.targetPending then { state with prefixComplete := true }
        else state
      | .assign => { state with inDefault := true, prefixComplete := true }
      | .openAngle =>
        if !state.inDefault || state.angleDepth > 0 ||
            defaultStartsTypeArguments input index (input.get (index - 1)).identifierLike
        then { state with angleDepth := state.angleDepth + 1 }
        else state
      | .closeAngle => { state with angleDepth := state.angleDepth - 1 }
      | _ => state
    if token.kind == .at then { updated with atPending := true, targetPending := false }
    else { updated with atPending := false, targetPending := state.atPending && token.identifierLike }

def objectExpressionAt (input : Input) (index : Nat) : Bool :=
  (input.get index).kind == .objectKeyword &&
    ((input.get (index + 1)).kind == .colon || (input.get (index + 1)).kind == .openBrace)

theorem objectExpressionAtIff :
    objectExpressionAt input index = true ↔
      (input.get index).kind = .objectKeyword ∧
        ((input.get (index + 1)).kind = .colon ∨ (input.get (index + 1)).kind = .openBrace) := by
  simp [objectExpressionAt]

def anonymousDefaultAt (input : Input) (index : Nat) : Bool :=
  (input.get (index - 1)).kind == .assign &&
    (if (input.get index).kind == .funKeyword then (input.get (index + 1)).kind == .openParen
     else objectExpressionAt input index)

def groupStackStep (stack : List Kind) (kind : Kind) : List Kind :=
  match kind with
  | .openParen => .closeParen :: stack
  | .openBracket => .closeBracket :: stack
  | .openBrace => .closeBrace :: stack
  | _ =>
    match stack with
    | expected :: rest => if kind == expected then rest else stack
    | [] => []

structure GroupResult where
  stop : Stop
  endIndex : Nat

def groupStopCode : Stop → Nat
  | .missingOpen => 0 | .closed => 1 | .recovery => 2 | .eof => 3

def groupStopAt (index : Nat) (stack : List Kind) (kind : Kind) (recover : Bool) : Option GroupResult :=
  if kind == .eof then some ⟨.eof, index⟩
  else if stack == [kind] then some ⟨.closed, index + 1⟩
  else if recover then some ⟨.recovery, index⟩
  else none

theorem groupStopConsumesMatchingClose (notEOF : closing ≠ .eof) :
    groupStopAt index [closing] closing recover = some ⟨.closed, index + 1⟩ := by
  simp [groupStopAt, notEOF]

theorem groupStopPreservesRecoveryBoundary
    (notEOF : kind ≠ .eof) (notClosing : stack ≠ [kind]) :
    groupStopAt index stack kind true = some ⟨.recovery, index⟩ := by
  simp [groupStopAt, notEOF, notClosing]

theorem groupStopPreservesEOF :
    groupStopAt index stack .eof recover = some ⟨.eof, index⟩ := by
  simp [groupStopAt]

theorem groupStackIgnoresMismatchedClose
    (close : kind = .closeParen ∨ kind = .closeBracket ∨ kind = .closeBrace)
    (mismatch : kind ≠ expected) :
    groupStackStep (expected :: rest) kind = expected :: rest := by
  rcases close with rfl | rfl | rfl <;> simp [groupStackStep, mismatch]

structure GroupQueries where
  declarationAt : Nat → IO Bool
  valuePrefixEnd : Nat → IO (Option Nat)
  whenPrefixEnd : Nat → IO (Option Nat)

def covers (endIndex : Option Nat) (index : Nat) : Bool :=
  endIndex.any fun stop => index < stop

theorem prefixExcludesEndIndex : covers (some endIndex) endIndex = false := by
  simp [covers]

def groupRecovers (outer newline declaration valuePrefix defaultExpression whenPrefix
    objectExpression anonymousFunction : Bool) : Bool :=
  outer && newline && declaration && !valuePrefix && !defaultExpression &&
    !whenPrefix && !objectExpression && !anonymousFunction

theorem groupDoesNotRecoverAtShieldedPrefix :
    groupRecovers outer newline declaration true defaultExpression whenPrefix
      objectExpression anonymousFunction = false := by
  simp [groupRecovers]

theorem groupOnlyRecoversAtOuterDeclaration
    (recover : groupRecovers outer newline declaration valuePrefix defaultExpression whenPrefix
      objectExpression anonymousFunction = true) :
    outer = true ∧ newline = true ∧ declaration = true := by
  simp [groupRecovers] at recover
  rcases recover with ⟨⟨⟨⟨⟨⟨⟨outer, newline⟩, declaration⟩, _⟩, _⟩, _⟩, _⟩, _⟩
  exact ⟨outer, newline, declaration⟩

inductive GroupStep where
  | stop (result : GroupResult)
  | advance (stack : List Kind) (state : ParameterState)

-- Separating the IO step keeps the group driver tail-recursive in generated C.
@[noinline] def groupStep (input : Input) (queries : GroupQueries) (index : Nat) (stack : List Kind)
    (parameters : Bool) (whenEnd : Option Nat) (state : ParameterState) : IO GroupStep := do
  let token := input.get index
  if let some stop := groupStopAt index stack token.kind false then return .stop stop

  let outer := stack.length == 1
  let prefixEnd ← if parameters && outer && !state.prefixComplete && token.newline then do
      if ← queries.declarationAt index then queries.valuePrefixEnd index else pure state.prefixEnd
    else pure state.prefixEnd
  let state := { state with prefixEnd }
  let valuePrefix := parameters && covers prefixEnd index
  let defaultExpression := parameters && state.inDefault && anonymousDefaultAt input index
  let whenPrefix := covers whenEnd index
  let recover ← if outer && token.newline then do
      let declaration ← queries.declarationAt index
      let candidate := groupRecovers outer token.newline declaration valuePrefix defaultExpression
        whenPrefix (objectExpressionAt input index) false
      pure (candidate && !anonymousFunctionAt input index)
    else pure false
  if let some stop := groupStopAt index stack token.kind recover then return .stop stop

  let state := if parameters && outer then state.step input index token else state
  return .advance (groupStackStep stack token.kind) state

def groupLookahead (input : Input) (queries : GroupQueries) (index : Nat) (stack : List Kind)
    (parameters : Bool) (whenEnd : Option Nat) (state : ParameterState) : Nat → IO GroupResult
  | 0 => pure ⟨.eof, index⟩
  | fuel + 1 => do
    match ← groupStep input queries index stack parameters whenEnd state with
    | .stop result => pure result
    | .advance stack state =>
      groupLookahead input queries (index + 1) stack parameters whenEnd state fuel
termination_by structural fuel => fuel

def scanBalancedGroup (input : Input) (queries : GroupQueries) (start : Nat)
    (opening closing : Kind) (parameters whenSubject : Bool) : IO GroupResult := do
  if (input.get start).kind != opening then return ⟨.missingOpen, start⟩
  let whenEnd ← if whenSubject then queries.whenPrefixEnd (start + 1) else pure none
  groupLookahead input queries (start + 1) [closing]
    (parameters && opening == .openParen && closing == .closeParen) whenEnd {} (input.count - start + 1)

inductive GenuineVerdict where
  | notDeclaration | declaration | overBudget
  deriving DecidableEq

structure GenuineResult where
  verdict : GenuineVerdict
  writes : List (Nat × Bool) := []
  budgetAt : Option Nat := none

inductive AnnotationPrefixResult where
  | complete (endIndex : Nat)
  | incomplete (recoveryIndex : Nat)
  | overBudget (index : Nat)

inductive AnnotationMode where
  | head
  | name
  | tail
  | angles (endIndex : Nat)
  | args (stack : List Kind)
  | finished

structure AnnotationCursor where
  index : Nat
  mode : AnnotationMode

def annotationAfterAngles (input : Input) (index : Nat) :
    AnnotationPrefixResult ⊕ AnnotationCursor :=
  if (input.get index).kind == .openParen then .inr ⟨index + 1, .args [.closeParen]⟩
  else .inl (.complete index)

def annotationNameCharge (input : Input) (index : Nat) :
    AnnotationPrefixResult ⊕ AnnotationCursor :=
  if (input.get index).identifierLike then .inr ⟨index, .name⟩
  else .inl (.incomplete index)

def annotationNextCharge (input : Input) (cursor : AnnotationCursor) :
    AnnotationPrefixResult ⊕ AnnotationCursor :=
  let index := cursor.index
  match cursor.mode with
  | .head =>
    if annotationName input index != index then .inr cursor else annotationNameCharge input index
  | .name => annotationNameCharge input index
  | .tail =>
    if qualifiedNameContinues input index then .inr cursor
    else
      let endIndex := endOfAnnotationTypeArguments input index
      if index < endIndex then .inr ⟨index, .angles endIndex⟩
      else annotationAfterAngles input index
  | .angles endIndex =>
    if index < endIndex then .inr cursor else annotationAfterAngles input index
  | .args _ => .inr cursor
  | .finished => .inl (.complete index)

def annotationArgumentBoundary (input : Input) (index : Nat) : Bool :=
  let token := input.get index
  match token.kind with
  | .funKeyword => (input.get (index + 1)).kind != .openParen
  | .objectKeyword => !objectExpressionAt input index
  | .declaration =>
    if token.classKeyword then
      (input.get (index - 1)).kind != .doubleColon && (input.get (index + 1)).identifierLike
    else token.annotationRecoveryKeyword
  | _ => false

def annotationArgsAtRecoveryBoundary (input : Input) (index : Nat) : List Kind → Bool
  | [_] => (input.get index).newline && annotationArgumentBoundary input index
  | _ => false

theorem annotationArgsRecoveryRequiresOuterLevel (input : Input) (index : Nat) (stack : List Kind) :
    annotationArgsAtRecoveryBoundary input index stack =
      (stack.length == 1 && (input.get index).newline && annotationArgumentBoundary input index) := by
  cases stack with
  | nil => simp [annotationArgsAtRecoveryBoundary]
  | cons _ rest => cases rest <;> simp [annotationArgsAtRecoveryBoundary]

def annotationChargedStep (input : Input) (cursor : AnnotationCursor) :
    AnnotationPrefixResult ⊕ AnnotationCursor :=
  let index := cursor.index
  match cursor.mode with
  | .head => .inr ⟨index + 2, .name⟩
  | .name => .inr ⟨index + 1, .tail⟩
  | .tail => .inr ⟨index + 2, .tail⟩
  | .angles _ => .inr { cursor with index := index + 1 }
  | .args stack =>
    let token := input.get index
    if token.kind == .eof || annotationArgsAtRecoveryBoundary input index stack
    then .inl (.incomplete index)
    else match groupStackStep stack token.kind with
      | [] => .inr ⟨index + 1, .finished⟩
      | stack => .inr ⟨index + 1, .args stack⟩
  | .finished => .inl (.complete index)

def scanAnnotationPrefix (input : Input) (cursor : AnnotationCursor) : Nat → AnnotationPrefixResult
  | 0 => match annotationNextCharge input cursor with
    | .inl result => result
    | .inr ready => .overBudget ready.index
  | work + 1 => match annotationNextCharge input cursor with
    | .inl result => result
    | .inr ready => match annotationChargedStep input ready with
      | .inl result => result
      | .inr next => scanAnnotationPrefix input next work

inductive AnnotationScanPath (input : Input) : AnnotationCursor → AnnotationCursor → Nat → Prop where
  | empty : AnnotationScanPath input cursor cursor 0
  | next (ready : annotationNextCharge input cursor = .inr charged)
      (advance : annotationChargedStep input charged = .inr nextCursor)
      (rest : AnnotationScanPath input nextCursor last steps) :
      AnnotationScanPath input cursor last (steps + 1)

theorem annotationScanChargesEachStep (path : AnnotationScanPath input cursor last steps) :
    scanAnnotationPrefix input cursor (steps + work) = scanAnnotationPrefix input last work := by
  induction path with
  | empty => simp
  | @next cursor charged nextCursor last steps ready advance rest ih =>
    simpa [Nat.add_right_comm steps 1 work, scanAnnotationPrefix, ready, advance] using ih

theorem annotationScanReportsNextCharge
    (path : AnnotationScanPath input cursor last work)
    (ready : annotationNextCharge input last = .inr charged) :
    scanAnnotationPrefix input cursor work = .overBudget charged.index := by
  simpa [scanAnnotationPrefix, ready] using (annotationScanChargesEachStep (work := 0) path)

theorem annotationScanStopsAtMissingName
    (path : AnnotationScanPath input cursor ⟨index, .name⟩ steps)
    (missing : (input.get index).identifierLike = false) :
    scanAnnotationPrefix input cursor (steps + work) = .incomplete index := by
  rw [annotationScanChargesEachStep path]
  cases work <;> simp [scanAnnotationPrefix, annotationNextCharge, annotationNameCharge, missing]

theorem annotationScanStopsAtMissingNameWithoutUseSite
    (noTarget : annotationName input index = index)
    (missing : (input.get index).identifierLike = false) :
    scanAnnotationPrefix input ⟨index, .head⟩ work = .incomplete index := by
  cases work <;> simp [scanAnnotationPrefix, annotationNextCharge, noTarget, annotationNameCharge, missing]

theorem annotationScanLeavesEOFInArguments
    (path : AnnotationScanPath input cursor ⟨index, .args stack⟩ steps)
    (eof : (input.get index).kind = .eof) :
    scanAnnotationPrefix input cursor (steps + (work + 1)) = .incomplete index := by
  rw [annotationScanChargesEachStep path]
  simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep, eof]

theorem annotationScanLeavesOuterRecoveryBoundary
    (path : AnnotationScanPath input cursor ⟨index, .args [closing]⟩ steps)
    (newline : (input.get index).newline = true)
    (boundary : annotationArgumentBoundary input index = true) :
    scanAnnotationPrefix input cursor (steps + (work + 1)) = .incomplete index := by
  rw [annotationScanChargesEachStep path]
  simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep,
    annotationArgsAtRecoveryBoundary, newline, boundary]

theorem annotationScanEndsJustAfterOuterClose
    (path : AnnotationScanPath input cursor ⟨index, .args [.closeParen]⟩ steps)
    (closing : (input.get index).kind = .closeParen) :
    scanAnnotationPrefix input cursor (steps + (work + 1)) = .complete (index + 1) := by
  rw [annotationScanChargesEachStep path]
  cases work <;> simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep,
    closing, annotationArgsAtRecoveryBoundary, annotationArgumentBoundary, groupStackStep]

def scanAnnotationArguments (input : Input) (opening : Nat) : GroupResult :=
  if (input.get opening).kind != .openParen then ⟨.missingOpen, opening⟩
  else
    let cursor : AnnotationCursor := ⟨opening + 1, .args [.closeParen]⟩
    match scanAnnotationPrefix input cursor (input.count - opening + 1) with
    | .complete index => ⟨.closed, index⟩
    | .incomplete index => ⟨if (input.get index).kind == .eof then .eof else .recovery, index⟩
    | .overBudget index => ⟨.eof, index⟩

theorem annotationArgumentScanNeverExhaustsInputBound
    (input : Input) (fuel index : Nat) (stack : List Kind) (stop : Nat)
    (enough : input.count + 1 - index < fuel) :
    scanAnnotationPrefix input ⟨index, .args stack⟩ fuel ≠ .overBudget stop := by
  induction fuel generalizing index stack with
  | zero => omega
  | succ fuel ih =>
    by_cases eof : (input.get index).kind = .eof
    · simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep, eof]
    · by_cases recover : annotationArgsAtRecoveryBoundary input index stack = true
      · simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep, eof, recover]
      · cases stepped : groupStackStep stack (input.get index).kind with
        | nil =>
          cases fuel <;>
            simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep, eof, recover, stepped]
        | cons head tail =>
          simp [scanAnnotationPrefix, annotationNextCharge, annotationChargedStep, eof, recover, stepped]
          apply ih
          have withinInput : index ≤ input.count := by
            apply Nat.le_of_not_gt
            intro beyond
            simp [Input.get, Nat.not_le.mpr beyond] at eof
          omega

theorem annotationArgumentsStopBeforeDeclaration
    (opens : (input.get opening).kind = .openParen)
    (path : AnnotationScanPath input ⟨opening + 1, .args [.closeParen]⟩
      ⟨index, .args [.closeParen]⟩ steps)
    (withinInput : steps < input.count - opening + 1)
    (newline : (input.get index).newline = true)
    (boundary : annotationArgumentBoundary input index = true) :
    scanAnnotationArguments input opening = ⟨.recovery, index⟩ := by
  have notEOF : (input.get index).kind ≠ .eof := by
    intro eof
    simp [annotationArgumentBoundary, eof] at boundary
  have fuel : input.count - opening + 1 =
      steps + (input.count - opening - steps + 1) := by omega
  simp only [scanAnnotationArguments, opens, beq_self_eq_true, ne_eq, not_true_eq_false, if_false]
  rw [fuel, annotationScanLeavesOuterRecoveryBoundary path newline boundary]
  simp [notEOF]

theorem annotationArgumentsStopBeforeEOF
    (opens : (input.get opening).kind = .openParen)
    (path : AnnotationScanPath input ⟨opening + 1, .args [.closeParen]⟩ ⟨index, .args stack⟩ steps)
    (withinInput : steps < input.count - opening + 1)
    (eof : (input.get index).kind = .eof) :
    scanAnnotationArguments input opening = ⟨.eof, index⟩ := by
  have fuel : input.count - opening + 1 =
      steps + (input.count - opening - steps + 1) := by omega
  simp only [scanAnnotationArguments, opens, beq_self_eq_true, ne_eq, not_true_eq_false, if_false]
  rw [fuel, annotationScanLeavesEOFInArguments path eof]
  simp [eof]

end TypeArguments.FFI
