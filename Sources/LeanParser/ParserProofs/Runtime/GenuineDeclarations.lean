import ParserProofs.Runtime.DeclarationDispatch

set_option warningAsError true

namespace TypeArguments.FFI

inductive GenuineMode where
  | prefix
  | annotation (mode : AnnotationMode)
  | contextParens (depth : Nat)

structure GenuineState where
  index : Nat
  mode : GenuineMode := .prefix
  prefixes : List Nat := []
  sawValue : Bool := false

def genuineNextCharge (input : Input) (state : GenuineState) : Option (Nat × GenuineMode) :=
  match state.mode with
  | .annotation mode =>
    match annotationNextCharge input ⟨state.index, mode⟩ with
    | .inl (.complete index) => some (index, .prefix)
    | .inl _ => none
    | .inr charged => some (charged.index, .annotation charged.mode)
  | _ => some (state.index, state.mode)

def genuineTerminal (input : Input) (start : Nat) (state : GenuineState) (index : Nat) : GenuineResult :=
  let token := input.get index
  let starts := isDeclarationStart input index token.kind &&
    !anonymousFunctionAt input index && !objectExpressionAt input index &&
    !((token.companionKeyword || token.kind == .companionKeyword) && (input.get (index + 1)).kind == .openParen)
  let declares := starts && (!state.sawValue || token.classKeyword || token.kind == .classKeyword)
  let prefixes := if state.sawValue && !declares then [start] else state.prefixes.reverse
  ⟨if declares then .declaration else .notDeclaration,
    prefixes.map (fun position => (position, declares)) ++ [(index, starts)], none⟩

def genuineIncomplete (state : GenuineState) : GenuineResult :=
  ⟨.declaration, state.prefixes.reverse.map (fun index => (index, true)), none⟩

def genuineStep (input : Input) (start : Nat) (state : GenuineState) (index : Nat)
    (mode : GenuineMode) : GenuineResult ⊕ GenuineState :=
  let token := input.get index
  let next := { state with index := index + 1 }
  match mode with
  | .prefix =>
    let visited := { next with prefixes := index :: state.prefixes }
    match token.kind with
    | .at => .inr { visited with mode := .annotation .head }
    | .modifier => .inr { visited with mode := .prefix, sawValue := state.sawValue || token.valueModifier }
    | .context =>
      .inr { visited with mode := if (input.get (index + 1)).kind == .openParen then .contextParens 0 else .prefix }
    | _ => .inl (genuineTerminal input start state index)
  | .annotation mode =>
    match annotationChargedStep input ⟨index, mode⟩ with
    | .inl (.complete endIndex) => .inr { state with index := endIndex, mode := .prefix }
    | .inl _ => .inl (genuineIncomplete state)
    | .inr after => .inr { state with index := after.index, mode := .annotation after.mode }
  | .contextParens depth =>
    match token.kind with
    | .eof => .inr { state with mode := .prefix }
    | .openParen => .inr { next with mode := .contextParens (depth + 1) }
    | .closeParen =>
      .inr { next with mode := if depth ≤ 1 then .prefix else .contextParens (depth - 1) }
    | _ => .inr { next with mode }

def genuineScan (input : Input) (start : Nat) (state : GenuineState) : Nat → GenuineResult
  | 0 => match genuineNextCharge input state with
    | none => genuineIncomplete state
    | some (index, _) => ⟨.overBudget, state.prefixes.reverse.map (fun position => (position, true)), some index⟩
  | work + 1 => match genuineNextCharge input state with
    | none => genuineIncomplete state
    | some (index, mode) => match genuineStep input start state index mode with
      | .inl result => result
      | .inr next => genuineScan input start next work

def genuineDeclarationAt (input : Input) (start work : Nat) : GenuineResult :=
  let token := input.get start
  if token.identifierLike && (input.get (start + 1)).kind == .at then ⟨.notDeclaration, [], none⟩
  else match token.genuineCache with
    | some declares => ⟨if declares then .declaration else .notDeclaration, [], none⟩
    | none => genuineScan input start ⟨start, .prefix, [], false⟩ work

inductive GenuineScanPath (input : Input) (start : Nat) :
    GenuineState → GenuineState → Nat → Prop where
  | empty : GenuineScanPath input start state state 0
  | next (ready : genuineNextCharge input state = some (index, mode))
      (advance : genuineStep input start state index mode = .inr nextState)
      (rest : GenuineScanPath input start nextState lastState steps) :
      GenuineScanPath input start state lastState (steps + 1)

theorem genuineScanChargesEachStep (path : GenuineScanPath input start state lastState steps) :
    genuineScan input start state (steps + work) = genuineScan input start lastState work := by
  induction path with
  | empty => simp
  | @next state index mode nextState lastState steps ready advance rest ih =>
    simpa [Nat.add_right_comm steps 1 work, genuineScan, ready, advance] using ih

theorem genuineScanReportsNextChargeAndCachesVisitedPrefixes
    (path : GenuineScanPath input start state lastState work)
    (ready : genuineNextCharge input lastState = some (index, mode)) :
    genuineScan input start state work =
      ⟨.overBudget, lastState.prefixes.reverse.map (fun position => (position, true)), some index⟩ := by
  simpa [genuineScan, ready] using (genuineScanChargesEachStep (work := 0) path)

theorem genuineLabelWinsOverCache
    (name : (input.get start).identifierLike = true)
    (atSign : (input.get (start + 1)).kind = .at) :
    genuineDeclarationAt input start work = ⟨.notDeclaration, [], none⟩ := by
  simp [genuineDeclarationAt, name, atSign]

theorem genuineInitialCacheSkipsScan
    (notLabel : ((input.get start).identifierLike && (input.get (start + 1)).kind == .at) = false)
    (hit : (input.get start).genuineCache = some declares) :
    genuineDeclarationAt input start work =
      ⟨if declares then .declaration else .notDeclaration, [], none⟩ := by
  simp [genuineDeclarationAt, notLabel, hit]

theorem genuineMissingAnnotationNameRecoversWithoutCharge
    (mode : state.mode = .annotation .name)
    (missing : (input.get state.index).identifierLike = false) :
    genuineScan input start state work = genuineIncomplete state := by
  cases work <;> simp [genuineScan, genuineNextCharge, annotationNextCharge, annotationNameCharge, mode, missing]

theorem genuineAnnotationUseSiteChargesOnlyTarget
    (head : state.mode = .annotation .head)
    (target : (input.get state.index).useSiteTarget = true)
    (colon : (input.get (state.index + 1)).kind = .colon) :
    genuineScan input start state (work + 1) =
      genuineScan input start { state with index := state.index + 2, mode := .annotation .name } work := by
  simp [genuineScan, genuineNextCharge, annotationNextCharge, head, annotationName, target, colon,
    genuineStep, annotationChargedStep]

theorem genuineAnnotationStartsAndRecordsPrefix
    (atSign : (input.get index).kind = .at) :
    genuineStep input start state index .prefix =
      .inr { state with index := index + 1, mode := .annotation .head, prefixes := index :: state.prefixes } := by
  simp [genuineStep, atSign]

theorem genuineAnnotationArgumentRecoversAtOuterBoundary
    (newline : (input.get index).newline = true)
    (boundary : annotationArgumentBoundary input index = true) :
    genuineStep input start state index (.annotation (.args [closing])) = .inl (genuineIncomplete state) := by
  simp [genuineStep, annotationChargedStep, annotationArgsAtRecoveryBoundary, newline, boundary]

theorem genuineModifierAccumulatesValueAndCacheIndex
    (modifier : (input.get index).kind = .modifier) :
    genuineStep input start state index .prefix =
      .inr { state with
        index := index + 1
        mode := .prefix
        prefixes := index :: state.prefixes
        sawValue := state.sawValue || (input.get index).valueModifier } := by
  simp [genuineStep, modifier]

theorem genuineContextEntersParens
    (context : (input.get index).kind = .context)
    (opening : (input.get (index + 1)).kind = .openParen) :
    genuineStep input start state index .prefix =
      .inr { state with index := index + 1, mode := .contextParens 0, prefixes := index :: state.prefixes } := by
  simp [genuineStep, context, opening]

theorem genuineContextLeavesGroupAtOuterClose
    (closing : (input.get index).kind = .closeParen) :
    genuineStep input start state index (.contextParens 1) =
      .inr { state with index := index + 1, mode := .prefix } := by
  simp [genuineStep, closing]

theorem genuineContextWithoutParensContinuesAtNextToken
    (context : (input.get index).kind = .context)
    (notOpening : (input.get (index + 1)).kind ≠ .openParen) :
    genuineStep input start state index .prefix =
      .inr { state with index := index + 1, mode := .prefix, prefixes := index :: state.prefixes } := by
  simp [genuineStep, context, notOpening]

theorem genuineTerminalAfterValueCannotPolluteSuffix
    (sawValue : state.sawValue = true)
    (notClass : (input.get index).classKeyword = false)
    (notClassKind : (input.get index).kind ≠ .classKeyword) :
    genuineTerminal input start state index =
      let token := input.get index
      let starts := isDeclarationStart input index token.kind &&
        !anonymousFunctionAt input index && !objectExpressionAt input index &&
        !((token.companionKeyword || token.kind == .companionKeyword) && (input.get (index + 1)).kind == .openParen)
      ⟨.notDeclaration, [(start, false), (index, starts)], none⟩ := by
  simp [genuineTerminal, sawValue, notClass, notClassKind]

@[export kswiftk_lean_annotation_prefix]
def annotationPrefixFrom (context count start : USize) (work : UInt32) : IO UInt64 := do
  let input := callbackInput context count
  match scanAnnotationPrefix input ⟨start.toNat + 1, .head⟩ work.toNat with
  | .complete index => return (index * 4).toUInt64
  | .incomplete index => return (index * 4 + 1).toUInt64
  | .overBudget index =>
    reportBudget context index.toUSize
    return (index * 4 + 2).toUInt64

def runGenuineDeclarationAt (context : USize) (input : Input) (start workLimit : Nat) : IO GenuineVerdict := do
  let result := genuineDeclarationAt input start workLimit
  if let some position := result.budgetAt then
    reportBudget context position.toUSize
  for (index, declares) in result.writes do
    recordCache context index.toUSize (index + 1).toUSize (if declares then 1 else 0)
  return result.verdict

def needsGenuineDeclarationScan (input : Input) (index : Nat) : Bool :=
  isAmbiguousDeclarationPrefix (input.get index).kind || anonymousFunctionAt input index

def genuineBoundaryFromVerdict (verdict : GenuineVerdict) : Bool :=
  verdict != .notDeclaration

def genuineDeclarationBoundary (input : Input) (index : Nat) (scan : IO GenuineVerdict) : IO Bool := do
  if needsGenuineDeclarationScan input index then
    return genuineBoundaryFromVerdict (← scan)
  else return true

theorem genuineDeclarationScanNeededIff :
    needsGenuineDeclarationScan input index = true ↔
      isAmbiguousDeclarationPrefix (input.get index).kind = true ∨ anonymousFunctionAt input index = true := by
  simp [needsGenuineDeclarationScan]

theorem genuineBoundarySkipsScanForOtherTokens
    (unambiguous : isAmbiguousDeclarationPrefix (input.get index).kind = false)
    (notAnonymous : anonymousFunctionAt input index = false) :
    genuineDeclarationBoundary input index probe = pure true := by
  simp [genuineDeclarationBoundary, needsGenuineDeclarationScan, unambiguous, notAnonymous]

theorem genuineBoundaryUsesScanForCandidates
    (candidate : isAmbiguousDeclarationPrefix (input.get index).kind = true ∨
      anonymousFunctionAt input index = true) :
    genuineDeclarationBoundary input index probe = (do return genuineBoundaryFromVerdict (← probe)) := by
  simp [genuineDeclarationBoundary, genuineDeclarationScanNeededIff.mpr candidate]

theorem genuineBoundaryAcceptsOverBudget
    (candidate : needsGenuineDeclarationScan input index = true)
    (exhausted : probe = pure .overBudget) :
    genuineDeclarationBoundary input index probe = pure true := by
  simp [genuineDeclarationBoundary, candidate, exhausted]
  rfl

theorem genuineBoundaryRejectsNotDeclaration
    (candidate : needsGenuineDeclarationScan input index = true)
    (rejected : probe = pure .notDeclaration) :
    genuineDeclarationBoundary input index probe = pure false := by
  simp [genuineDeclarationBoundary, candidate, rejected]
  rfl

end TypeArguments.FFI
