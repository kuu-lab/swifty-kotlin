import ParserProofs.Runtime.TokenInput

set_option warningAsError true

namespace TypeArguments.FFI

def annotationName (input : Input) (start : Nat) : Nat :=
  if (input.get start).useSiteTarget && (input.get (start + 1)).kind == .colon
  then start + 2 else start

def endOfAnnotationName (input : Input) (name : Nat) : Nat :=
  if (input.get name).identifierLike then
    skipQualifiedName input (name + 1) (input.count - name)
  else name

def endOfAnnotationTypeArguments (input : Input) (index : Nat) : Nat :=
  if (input.get index).kind == .openAngle then offsetPastAngles input index else index

theorem annotationTypeArgumentsStopAfterFirstOuterClose
    (opens : (input.get start).kind = .openAngle)
    (path : AngleScanPath input start 0 {} steps 1 depth)
    (enough : steps < input.count - start + 1)
    (outer : depth.isNested = false)
    (close : (input.get (start + steps)).kind = .closeAngle) :
    endOfAnnotationTypeArguments input start = start + steps + 1 := by
  have fuel : input.count - start + 1 = steps + (input.count - start - steps + 1) := by omega
  simp only [endOfAnnotationTypeArguments, opens, beq_self_eq_true, if_true, offsetPastAngles]
  rw [fuel, skipAnglesThroughPath path]
  simp [skipAngles, angleStep, outer, close]

theorem annotationTypeArgumentsLeaveEOF
    (opens : (input.get start).kind = .openAngle)
    (path : AngleScanPath input start 0 {} steps angles depth)
    (enough : steps < input.count - start + 1)
    (eof : (input.get (start + steps)).kind = .eof) :
    endOfAnnotationTypeArguments input start = start + steps := by
  have fuel : input.count - start + 1 = steps + (input.count - start - steps + 1) := by omega
  simp only [endOfAnnotationTypeArguments, opens, beq_self_eq_true, if_true, offsetPastAngles]
  rw [fuel, skipAnglesThroughPath path]
  simp [skipAngles, angleStep, eof]

def annotationTail (input : Input) (start : Nat) : Option Nat := do
  let name := annotationName input start
  if !(input.get name).identifierLike then none else
    let afterAngles := endOfAnnotationTypeArguments input (endOfAnnotationName input name)
    some (if (input.get afterAngles).kind == .openParen then
        offsetPastParens input afterAngles none
      else afterAngles)

theorem annotationNameSkipsUseSite
    (target : (input.get start).useSiteTarget = true)
    (colon : (input.get (start + 1)).kind = .colon) :
    annotationName input start = start + 2 := by
  simp [annotationName, target, colon]

theorem annotationTailRequiresName
    (missing : (input.get (annotationName input start)).identifierLike = false) :
    annotationTail input start = none := by
  simp [annotationTail, missing]

theorem annotationTailAfterName
    (name : (input.get (annotationName input start)).identifierLike = true) :
    annotationTail input start = some (
      let name := annotationName input start
      let qualified := skipQualifiedName input (name + 1) (input.count - name)
      let typed := if (input.get qualified).kind == .openAngle
                   then offsetPastAngles input qualified else qualified
      if (input.get typed).kind == .openParen then offsetPastParens input typed none else typed) := by
  simp [annotationTail, endOfAnnotationName, endOfAnnotationTypeArguments, name]

def valueParameterAnnotationSuffix (input : Input) (index : Nat) : Option Nat :=
  let afterAngles := if (input.get index).kind == .openAngle then offsetPastAngles input index else index
  if (input.get afterAngles).kind == .openParen then
    let endIndex := offsetPastParens input afterAngles none
    if (input.get (endIndex - 1)).kind == .closeParen then some endIndex else none
  else some afterAngles

def valueParameterPrefixPosition (input : Input) (index : Nat) (qualified : Bool) :
    Option (Nat × Bool) :=
  if !qualified then some (index, false)
  else if (input.get index).kind == .dot && (input.get (index + 1)).identifierLike then
    some (index, true)
  else (valueParameterAnnotationSuffix input index).map fun next => (next, false)

inductive ValueParameterPrefixResult where
  | found (endIndex : Nat)
  | rejected
  | budget (index : Nat)

def isParameterName (token : LexToken) : Bool :=
  token.kind == .identifier || token.kind == .modifier || token.softKeyword

def valueParameterNameAt (input : Input) (index : Nat) : Bool :=
  isParameterName (input.get index) && (input.get (index + 1)).kind == .colon

def valueParameterPrefixStep (input : Input) (index : Nat) (dot : Bool) :
    ValueParameterPrefixResult ⊕ (Nat × Bool) :=
  if dot then .inr (index + 2, true)
  else
    let token := input.get index
    if token.kind == .at then
      let name := annotationName input (index + 1)
      if (input.get name).identifierLike then .inr (name + 1, true) else .inl .rejected
    else if valueParameterNameAt input index then .inl (.found (index + 2))
    else if token.parameterModifier then .inr (index + 1, false)
    else
      let name := if token.bindingKeyword then index + 1 else index
      .inl (if valueParameterNameAt input name then .found (name + 2) else .rejected)

def valueParameterPrefixLookahead (input : Input) (index : Nat) (qualified : Bool) :
    Nat → ValueParameterPrefixResult
  | 0 => match valueParameterPrefixPosition input index qualified with
    | none => .rejected
    | some (position, _) => .budget position
  | work + 1 => match valueParameterPrefixPosition input index qualified with
    | none => .rejected
    | some (position, dot) => match valueParameterPrefixStep input position dot with
      | .inl result => result
      | .inr (next, qualified) => valueParameterPrefixLookahead input next qualified work

inductive ValueParameterPrefixPath (input : Input) :
    Nat → Bool → Nat → Bool → Nat → Prop where
  | empty : ValueParameterPrefixPath input index qualified index qualified 0
  | step (ready : valueParameterPrefixPosition input index qualified = some (position, dot))
      (advance : valueParameterPrefixStep input position dot = .inr (next, nextQualified))
      (rest : ValueParameterPrefixPath input next nextQualified endIndex endQualified steps) :
      ValueParameterPrefixPath input index qualified endIndex endQualified (steps + 1)

theorem valueParameterPrefixChargesEachStep
    (path : ValueParameterPrefixPath input index qualified endIndex endQualified steps) :
    valueParameterPrefixLookahead input index qualified (steps + work) =
      valueParameterPrefixLookahead input endIndex endQualified work := by
  induction path with
  | empty => simp
  | @step index qualified position dot next nextQualified endIndex endQualified steps ready advance rest ih =>
    simpa [Nat.add_right_comm steps 1 work, valueParameterPrefixLookahead, ready, advance] using ih

theorem valueParameterPrefixExhaustsAtNextCharge
    (path : ValueParameterPrefixPath input index qualified endIndex endQualified work)
    (ready : valueParameterPrefixPosition input endIndex endQualified = some (position, dot)) :
    valueParameterPrefixLookahead input index qualified work = .budget position := by
  simpa [valueParameterPrefixLookahead, ready] using
    (valueParameterPrefixChargesEachStep (work := 0) path)

theorem valueParameterPrefixChargesQualifiedDot
    (dot : (input.get index).kind = .dot) (name : (input.get (index + 1)).identifierLike = true) :
    valueParameterPrefixLookahead input index true 0 = .budget index ∧
      valueParameterPrefixLookahead input index true (work + 1) =
        valueParameterPrefixLookahead input (index + 2) true work := by
  simp [valueParameterPrefixLookahead, valueParameterPrefixPosition, dot, name, valueParameterPrefixStep]

theorem valueParameterPrefixRejectsMissingAnnotationName
    (atSign : (input.get index).kind = .at)
    (missing : (input.get (annotationName input (index + 1))).identifierLike = false) :
    valueParameterPrefixLookahead input index false (work + 1) = .rejected := by
  simp [valueParameterPrefixLookahead, valueParameterPrefixPosition, valueParameterPrefixStep, atSign, missing]

theorem valueParameterPrefixFinishesAnnotationBeforeNextCharge
    (notDot : ((input.get index).kind == .dot && (input.get (index + 1)).identifierLike) = false)
    (suffix : valueParameterAnnotationSuffix input index = some next) :
    valueParameterPrefixLookahead input index true work =
      valueParameterPrefixLookahead input next false work := by
  cases work <;> simp [valueParameterPrefixLookahead, valueParameterPrefixPosition, notDot, suffix]

theorem valueParameterPrefixRejectsAnnotationWithoutFinalParen
    (notDot : (input.get index).kind ≠ .dot)
    (afterAnglesEq : afterAngles =
      if (input.get index).kind == .openAngle then offsetPastAngles input index else index)
    (opening : (input.get afterAngles).kind = .openParen)
    (missing : (input.get (offsetPastParens input afterAngles none - 1)).kind ≠ .closeParen) :
    valueParameterPrefixLookahead input index true work = .rejected := by
  subst afterAngles
  simp only [beq_iff_eq] at opening missing
  cases work <;>
    simp [valueParameterPrefixLookahead, valueParameterPrefixPosition, valueParameterAnnotationSuffix,
      notDot, opening, missing]

theorem valueParameterPrefixAfterAnnotationAnglesAtEOF
    (angled : (input.get index).kind = .openAngle)
    (eof : input.get (offsetPastAngles input index) = {}) :
    valueParameterPrefixLookahead input index true 0 = .budget (offsetPastAngles input index) ∧
      valueParameterPrefixLookahead input index true (work + 1) = .rejected := by
  simp [valueParameterPrefixLookahead, valueParameterPrefixPosition, valueParameterAnnotationSuffix,
    valueParameterPrefixStep, valueParameterNameAt, isParameterName, angled, eof]

structure WhenSubjectTypeDepth where
  groups : GroupDepth := {}
  angle : Nat := 0

def WhenSubjectTypeDepth.isTopLevel (depth : WhenSubjectTypeDepth) : Bool :=
  depth.angle == 0 && depth.groups.paren == 0 && depth.groups.bracket == 0 && depth.groups.brace == 0

def WhenSubjectTypeDepth.step (depth : WhenSubjectTypeDepth) (kind : Kind) : WhenSubjectTypeDepth :=
  match kind with
  | .openAngle => { depth with angle := depth.angle + 1 }
  | .closeAngle => { depth with angle := depth.angle - 1 }
  | _ => { depth with groups := depth.groups.step kind }

structure WhenSubjectTypeState where
  depth : WhenSubjectTypeDepth := {}
  -- A non-declaration modifier run is visible to subsequent steps before its cache effect is applied.
  modifierCacheEnd : Nat := 0
  effectsRev : List DeclarationEffect := []

inductive WhenSubjectPrefixResult where
  | found (assignIndex : Nat)
  | rejected
  | declarationBoundary
  | budget (index : Nat)

def whenSubjectDeclarationAt (input : Input) (index cacheEnd workLimit : Nat) :
    Bool × List DeclarationEffect :=
  if index < cacheEnd && (input.get index).kind == .modifier then (false, [])
  else likelyDeclarationAt input index workLimit

theorem whenSubjectModifierUsesCurrentCache
    (modifier : (input.get index).kind = .modifier) (outsidePending : cacheEnd ≤ index)
    (cached : (input.get index).modifierCache = some declares) :
    whenSubjectDeclarationAt input index cacheEnd workLimit = (declares, []) := by
  cases workLimit <;>
    simp [whenSubjectDeclarationAt, likelyDeclarationAt, modifier, Nat.not_lt.mpr outsidePending,
      modifierDeclarationAt, modifierLookahead, cached]

theorem whenSubjectModifierScansFromCurrentToken
    (modifier : (input.get index).kind = .modifier) (outsidePending : cacheEnd ≤ index)
    (path : UncachedModifiers input index visited)
    (miss : (input.get (index + visited)).modifierCache = none)
    (terminal : (input.get (index + visited)).kind ≠ .modifier) :
    whenSubjectDeclarationAt input index cacheEnd (visited + (work + 1)) =
      let declares := isDeclarationStart input (index + visited) (input.get (index + visited)).kind
      (declares, [.cache ⟨index, index + visited + 1, declares⟩]) := by
  simp [whenSubjectDeclarationAt, likelyDeclarationAt, modifier, Nat.not_lt.mpr outsidePending,
    modifierDeclarationCachesThroughTerminal path miss terminal]

theorem whenSubjectModifierUsesPendingCache
    (modifier : (input.get index).kind = .modifier) (pending : index < cacheEnd) :
    whenSubjectDeclarationAt input index cacheEnd workLimit = (false, []) := by
  simp [whenSubjectDeclarationAt, modifier, pending]

def whenSubjectTypeStep (input : Input) (index workLimit : Nat) (state : WhenSubjectTypeState) :
    (WhenSubjectPrefixResult × List DeclarationEffect) ⊕ WhenSubjectTypeState :=
  let token := input.get index
  let advanced := { state with depth := state.depth.step token.kind }
  if token.kind == .eof then .inl (.rejected, state.effectsRev)
  else if state.depth.isTopLevel then
    if token.kind == .assign then .inl (.found index, state.effectsRev)
    else if token.kind == .closeParen || token.kind == .openBrace || token.kind == .comma then
      .inl (.rejected, state.effectsRev)
    else if token.newline then
      let (declares, effects) := whenSubjectDeclarationAt input index state.modifierCacheEnd workLimit
      let effectsRev := effects.reverse ++ state.effectsRev
      if declares then .inl (.declarationBoundary, effectsRev)
      else
        let cacheEnd := match effects with
          | [.cache run] => run.endIndex
          | _ => state.modifierCacheEnd
        .inr { advanced with modifierCacheEnd := cacheEnd, effectsRev }
    else .inr advanced
  else .inr advanced

theorem whenSubjectTypeContextBoundaryIff
    (context : (input.get index).kind = .context)
    (top : state.depth.isTopLevel = true)
    (newline : (input.get index).newline = true) :
    whenSubjectTypeStep input index workLimit state = .inl (.declarationBoundary, state.effectsRev) ↔
      (input.get (index + 1)).kind = .openParen := by
  by_cases next : (input.get (index + 1)).kind = .openParen <;>
    simp [whenSubjectTypeStep, top, newline, whenSubjectDeclarationAt, context,
      likelyContextDeclarationNeedsParens (workLimit := workLimit) context, next]

theorem whenSubjectTypeContinuesAfterNonDeclarationModifier
    (modifier : (input.get index).kind = .modifier)
    (top : state.depth.isTopLevel = true)
    (newline : (input.get index).newline = true)
    (probe : whenSubjectDeclarationAt input index state.modifierCacheEnd workLimit =
      (false, [.cache run])) :
    whenSubjectTypeStep input index workLimit state = .inr
      { depth := state.depth.step .modifier, modifierCacheEnd := run.endIndex,
        effectsRev := .cache run :: state.effectsRev } := by
  simp [whenSubjectTypeStep, modifier, top, newline, probe]

def whenSubjectTypeLookahead (input : Input) (index workLimit : Nat)
    (state : WhenSubjectTypeState) : Nat → WhenSubjectPrefixResult × List DeclarationEffect
  | 0 => (.budget index, state.effectsRev)
  | work + 1 =>
    match whenSubjectTypeStep input index workLimit state with
    | .inl result => result
    | .inr next => whenSubjectTypeLookahead input (index + 1) workLimit next work

def startsMultilineContextFunctionType (input : Input) (index work : Nat) : Bool :=
  let token := input.get index
  if token.kind != .context || !token.newline || (input.get (index + 1)).kind != .openParen then
    false
  else
    let parameters := offsetPastParens input (index + 1) (some (work - 1))
    if parameters ≤ index + 1 || (input.get parameters).kind != .openParen then
      false
    else
      let arrow := offsetPastParens input parameters (some (work - (parameters - index)))
      parameters < arrow && arrow < index + work && (input.get arrow).kind == .arrow

def whenSubjectPrefixLookahead (input : Input) (subject work : Nat) :
    WhenSubjectPrefixResult × List DeclarationEffect :=
  if !(input.get subject).valKeyword || !isParameterName (input.get (subject + 1)) then (.rejected, [])
  else
    let afterName := subject + 2
    match (input.get afterName).kind with
    | .assign => (.found afterName, [])
    | .colon =>
      let typeStart := afterName + 1
      if startsMultilineContextFunctionType input typeStart work then
        whenSubjectTypeLookahead input (typeStart + 1) work {} (work - 1)
      else
        whenSubjectTypeLookahead input typeStart work {} work
    | _ => (.rejected, [])

inductive WhenSubjectTypePath (input : Input) (workLimit : Nat) :
    Nat → WhenSubjectTypeState → Nat → WhenSubjectTypeState → Prop where
  | empty : WhenSubjectTypePath input workLimit index state 0 state
  | step (advance : whenSubjectTypeStep input index workLimit state = .inr next)
      (rest : WhenSubjectTypePath input workLimit (index + 1) next steps endState) :
      WhenSubjectTypePath input workLimit index state (steps + 1) endState

theorem whenSubjectTypeChargesEachToken
    (path : WhenSubjectTypePath input workLimit index state steps endState) :
    whenSubjectTypeLookahead input index workLimit state (steps + work) =
      whenSubjectTypeLookahead input (index + steps) workLimit endState work := by
  induction path with
  | empty => simp
  | @step index state next steps endState advance rest ih =>
    simpa [Nat.add_right_comm steps 1 work, Nat.add_right_comm index 1 steps,
      whenSubjectTypeLookahead, advance] using ih

theorem whenSubjectTypeExhaustsAtNextToken
    (path : WhenSubjectTypePath input workLimit index state work endState) :
    whenSubjectTypeLookahead input index workLimit state work = (.budget (index + work), endState.effectsRev) := by
  simpa [whenSubjectTypeLookahead] using (whenSubjectTypeChargesEachToken (work := 0) path)

theorem whenSubjectTypeStopsBeforeAssign
    (path : WhenSubjectTypePath input workLimit index state steps endState)
    (top : endState.depth.isTopLevel = true) (assign : (input.get (index + steps)).kind = .assign) :
    whenSubjectTypeLookahead input index workLimit state (steps + (work + 1)) =
      (.found (index + steps), endState.effectsRev) := by
  rw [whenSubjectTypeChargesEachToken path]
  simp [whenSubjectTypeLookahead, whenSubjectTypeStep, top, assign]

theorem whenSubjectTypeStepFound
    (found : whenSubjectTypeStep input index workLimit state = .inl (.found endIndex, effectsRev)) :
    endIndex = index ∧ state.depth.isTopLevel = true ∧ (input.get index).kind = .assign := by
  unfold whenSubjectTypeStep at found
  dsimp only at found
  split at found
  · cases found
  · split at found
    · split at found
      · simp_all
      · split at found
        · cases found
        · split at found
          · split at found <;> cases found
          · cases found
    · cases found

theorem whenSubjectTypeFoundAtFirstAssign
    (found : whenSubjectTypeLookahead input index workLimit state work = (.found endIndex, effectsRev)) :
    ∃ steps endState, steps < work ∧ WhenSubjectTypePath input workLimit index state steps endState ∧
      endIndex = index + steps ∧ endState.depth.isTopLevel = true ∧ (input.get endIndex).kind = .assign := by
  induction work generalizing index state with
  | zero => simp [whenSubjectTypeLookahead] at found
  | succ work ih =>
    cases step : whenSubjectTypeStep input index workLimit state with
    | inl _ =>
      have direct : whenSubjectTypeStep input index workLimit state = .inl (.found endIndex, effectsRev) := by
        simpa [whenSubjectTypeLookahead, step] using found
      obtain ⟨rfl, top, eq⟩ := whenSubjectTypeStepFound direct
      exact ⟨0, state, Nat.zero_lt_succ _, .empty, rfl, top, eq⟩
    | inr next =>
      have continued :
          whenSubjectTypeLookahead input (index + 1) workLimit next work = (.found endIndex, effectsRev) := by
        simpa [whenSubjectTypeLookahead, step] using found
      obtain ⟨steps, endState, bounded, path, reached, top, eq⟩ := ih continued
      exact ⟨steps + 1, endState, by omega, .step step path, by omega, top, eq⟩

theorem whenSubjectPrefixStopsBeforeUntypedAssign
    (val : (input.get subject).valKeyword = true)
    (name : isParameterName (input.get (subject + 1)) = true)
    (assign : (input.get (subject + 2)).kind = .assign) :
    whenSubjectPrefixLookahead input subject work = (.found (subject + 2), []) := by
  simp [whenSubjectPrefixLookahead, val, name, assign]

theorem whenSubjectTypeRejectsAtDeclaration
    (path : WhenSubjectTypePath input workLimit index state steps endState)
    (top : endState.depth.isTopLevel = true)
    (newline : (input.get (index + steps)).newline = true)
    (boundary : whenSubjectDeclarationAt input (index + steps) endState.modifierCacheEnd workLimit =
      (true, effects)) :
    whenSubjectTypeLookahead input index workLimit state (steps + (work + 1)) =
      (.declarationBoundary, effects.reverse ++ endState.effectsRev) := by
  rw [whenSubjectTypeChargesEachToken path]
  have notTerminator :
      let kind := (input.get (index + steps)).kind
      kind ≠ .eof ∧ kind ≠ .assign ∧ kind ≠ .closeParen ∧ kind ≠ .openBrace ∧ kind ≠ .comma := by
    dsimp only
    refine ⟨?_, ?_, ?_, ?_, ?_⟩ <;> intro h <;>
      simp [whenSubjectDeclarationAt, likelyDeclarationAt, h, isDeclarationStart] at boundary
  obtain ⟨notEOF, notAssign, notClose, notBrace, notComma⟩ := notTerminator
  simp [whenSubjectTypeLookahead, whenSubjectTypeStep, top, newline, boundary,
    notEOF, notAssign, notClose, notBrace, notComma]

end TypeArguments.FFI
