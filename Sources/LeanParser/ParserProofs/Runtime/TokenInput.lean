import ParserProofs.TypeArgumentConsumption

set_option warningAsError true

namespace TypeArguments.FFI

inductive Kind where
  | other | openAngle | closeAngle | at | dot | colon
  | openParen | closeParen | openBracket | closeBracket | openBrace | closeBrace
  | templateStart | templateEnd | context | modifier | declaration | varianceIn | eof
  | identifier | star | varianceOut | comma | question | questionDot | doubleColon
  | assign | funKeyword | objectKeyword | semicolon
  | bang | bangBang | isKeyword | literal | expressionKeyword | plus | minus | stringStart
  | catchKeyword | finallyKeyword | elseKeyword | asKeyword | byKeyword
  | slash | percent | ampAmp | barBar | equalEqual | bangEqual
  | tripleEqual | notTripleEqual | lessOrEqual | greaterOrEqual
  | plusAssign | minusAssign | starAssign | slashAssign | percentAssign
  | dotDot | dotDotLt | questionQuestion | questionColon | arrow
  | enumKeyword | importKeyword | returnKeyword | companionKeyword | packageKeyword
  | classKeyword | interfaceKeyword | propertyKeyword | typeAliasKeyword | constructorKeyword | accessorKeyword
  | loopKeyword | whenKeyword | softWhenKeyword | companionNameKeyword | whereKeyword
  | constructorDelegationKeyword | nonToken
  deriving DecidableEq

structure LexToken where
  kind : Kind := .eof
  newline : Bool := false
  identifierLike : Bool := false
  useSiteTarget : Bool := false
  modifierCache : Option Bool := none
  softKeyword : Bool := false
  parameterModifier : Bool := false
  bindingKeyword : Bool := false
  valKeyword : Bool := false
  classKeyword : Bool := false
  companionKeyword : Bool := false
  valueModifier : Bool := false
  annotationRecoveryKeyword : Bool := false
  genuineCache : Option Bool := none
  receiverUseSiteTarget : Bool := false
  constructorKeyword : Bool := false
  getterKeyword : Bool := false
  setterKeyword : Bool := false
  visibilityModifier : Bool := false
  inlineModifier : Bool := false
  keyword : Bool := false
  fieldKeyword : Bool := false

structure Input where
  count : Nat
  read : Nat → LexToken

def Input.get (input : Input) (index : Nat) : LexToken :=
  if index ≤ input.count then input.read index else {}

def isDeclarationStart (input : Input) (index : Nat) : Kind → Bool
  | .context => (input.get (index + 1)).kind == .openParen
  | .at | .modifier | .declaration | .funKeyword | .objectKeyword => true
  | _ => false

structure CacheRun where
  start : Nat
  endIndex : Nat
  declares : Bool

structure Effects where
  runs : List CacheRun := []
  budgetAt : Option Nat := none

def modifierLookahead (input : Input) (index : Nat) : Nat → Bool × Nat × Option Nat
  | 0 =>
    match (input.get index).modifierCache with
    | some declares => (declares, index, none)
    | none => (true, index, some index)
  | n + 1 =>
    let token := input.get index
    match token.modifierCache with
    | some declares => (declares, index, none)
    | none =>
      if token.kind == .modifier then modifierLookahead input (index + 1) n
      else (isDeclarationStart input index token.kind, index + 1, none)

theorem modifierLookaheadStaysWithinBudget (input : Input) (index work : Nat) :
    index ≤ (modifierLookahead input index work).2.1 ∧
      (modifierLookahead input index work).2.1 ≤ index + work := by
  induction work generalizing index with
  | zero =>
    cases hit : (input.get index).modifierCache <;> simp [modifierLookahead, hit]
  | succ work ih =>
    cases hit : (input.get index).modifierCache with
    | some cached => simp [modifierLookahead, hit]
    | none =>
      by_cases modifier : (input.get index).kind = .modifier
      · simp [modifierLookahead, hit, modifier]
        have bounds := ih (index + 1)
        omega
      · simp [modifierLookahead, hit, modifier]

inductive UncachedModifiers (input : Input) : Nat → Nat → Prop where
  | empty : UncachedModifiers input index 0
  | next (modifier : (input.get index).kind = .modifier)
      (miss : (input.get index).modifierCache = none)
      (rest : UncachedModifiers input (index + 1) visited) :
      UncachedModifiers input index (visited + 1)

theorem modifierLookaheadTraversesPrefix (path : UncachedModifiers input index visited) :
    modifierLookahead input index (visited + work) =
      modifierLookahead input (index + visited) work := by
  induction path with
  | empty => simp
  | @next index visited modifier miss rest ih =>
    have fuelEq : visited + 1 + work = visited + work + 1 := by omega
    rw [fuelEq]
    simpa [modifierLookahead, modifier, miss, Nat.add_assoc, Nat.add_comm 1] using ih

theorem modifierLookaheadUsesFirstCache
    (path : UncachedModifiers input index visited)
    (hit : (input.get (index + visited)).modifierCache = some declares) :
    modifierLookahead input index (visited + work) = (declares, index + visited, none) := by
  rw [modifierLookaheadTraversesPrefix path]
  cases work <;> simp [modifierLookahead, hit]

theorem modifierLookaheadExhaustsAtFirstUnchargedToken
    (path : UncachedModifiers input index work)
    (miss : (input.get (index + work)).modifierCache = none) :
    modifierLookahead input index work = (true, index + work, some (index + work)) := by
  have finish := modifierLookaheadTraversesPrefix (work := 0) path
  simpa [modifierLookahead, miss] using finish

theorem modifierLookaheadChargesTerminal
    (path : UncachedModifiers input index visited)
    (miss : (input.get (index + visited)).modifierCache = none)
    (terminal : (input.get (index + visited)).kind ≠ .modifier) :
    modifierLookahead input index (visited + (work + 1)) =
      (isDeclarationStart input (index + visited) (input.get (index + visited)).kind,
        index + visited + 1, none) := by
  rw [modifierLookaheadTraversesPrefix path]
  simp [modifierLookahead, miss, terminal]

inductive DeclarationEffect where
  | budget (index : Nat)
  | cache (run : CacheRun)

def modifierDeclarationAt (input : Input) (index workLimit : Nat) : Bool × List DeclarationEffect :=
  let (declares, endIndex, budgetAt) := modifierLookahead input index workLimit
  match budgetAt with
  | some exhausted => (declares, [.budget exhausted, .cache ⟨index, max endIndex (index + 1), declares⟩])
  | none =>
    (declares, if index < endIndex then [.cache ⟨index, endIndex, declares⟩] else [])

theorem modifierDeclarationCachesOnlyBeforeHit
    (path : UncachedModifiers input index visited)
    (hit : (input.get (index + visited)).modifierCache = some declares) :
    modifierDeclarationAt input index (visited + work) =
      (declares, if 0 < visited then [.cache ⟨index, index + visited, declares⟩] else []) := by
  unfold modifierDeclarationAt
  rw [modifierLookaheadUsesFirstCache path hit]
  simp

theorem modifierDeclarationCachesThroughTerminal
    (path : UncachedModifiers input index visited)
    (miss : (input.get (index + visited)).modifierCache = none)
    (terminal : (input.get (index + visited)).kind ≠ .modifier) :
    modifierDeclarationAt input index (visited + (work + 1)) =
      let declares := isDeclarationStart input (index + visited) (input.get (index + visited)).kind
      (declares, [.cache ⟨index, index + visited + 1, declares⟩]) := by
  have nonempty : index < index + visited + 1 := by omega
  simp [modifierDeclarationAt, modifierLookaheadChargesTerminal path miss terminal, nonempty]

theorem modifierDeclarationContextTerminal
    (path : UncachedModifiers input index visited)
    (miss : (input.get (index + visited)).modifierCache = none)
    (context : (input.get (index + visited)).kind = .context) :
    modifierDeclarationAt input index (visited + (work + 1)) =
      let declares := (input.get (index + visited + 1)).kind == .openParen
      (declares, [.cache ⟨index, index + visited + 1, declares⟩]) := by
  have terminal : (input.get (index + visited)).kind ≠ .modifier := by simp [context]
  simpa [context, isDeclarationStart] using
    (modifierDeclarationCachesThroughTerminal (work := work) path miss terminal)

theorem modifierDeclarationContextBoundaryIff
    (path : UncachedModifiers input index visited)
    (miss : (input.get (index + visited)).modifierCache = none)
    (context : (input.get (index + visited)).kind = .context) :
    (modifierDeclarationAt input index (visited + (work + 1))).1 = true ↔
      (input.get (index + visited + 1)).kind = .openParen := by
  rw [modifierDeclarationContextTerminal path miss context]
  simp

theorem modifierDeclarationReportsThenCaches
    (path : UncachedModifiers input index work)
    (miss : (input.get (index + work)).modifierCache = none) (positive : 0 < work) :
    modifierDeclarationAt input index work =
      (true, [.budget (index + work), .cache ⟨index, index + work, true⟩]) := by
  have ordered : index + 1 ≤ index + work := by omega
  simp [modifierDeclarationAt, modifierLookaheadExhaustsAtFirstUnchargedToken path miss,
    Nat.max_eq_left ordered]

def likelyDeclarationAt (input : Input) (index workLimit : Nat) : Bool × List DeclarationEffect :=
  match (input.get index).kind with
  | .modifier => modifierDeclarationAt input index workLimit
  | kind => (isDeclarationStart input index kind, [])

theorem likelyContextDeclarationNeedsParens
    (context : (input.get index).kind = .context) :
    likelyDeclarationAt input index workLimit =
      ((input.get (index + 1)).kind == .openParen, []) := by
  simp [likelyDeclarationAt, isDeclarationStart, context]

def qualifiedNameContinues (input : Input) (index : Nat) : Bool :=
  (input.get index).kind == .dot && (input.get (index + 1)).identifierLike

def skipQualifiedName (input : Input) (index : Nat) : Nat → Nat
  | 0 => index
  | n + 1 =>
    if qualifiedNameContinues input index then
      skipQualifiedName input (index + 2) n
    else index

structure GroupDepth where
  paren : Nat := 0
  bracket : Nat := 0
  brace : Nat := 0
  template : Nat := 0

def GroupDepth.isNested (depth : GroupDepth) : Bool :=
  depth.paren > 0 || depth.bracket > 0 || depth.brace > 0 || depth.template > 0

def GroupDepth.step (depth : GroupDepth) : Kind → GroupDepth
  | .openParen => { depth with paren := depth.paren + 1 }
  | .closeParen => { depth with paren := depth.paren - 1 }
  | .openBracket => { depth with bracket := depth.bracket + 1 }
  | .closeBracket => { depth with bracket := depth.bracket - 1 }
  | .openBrace => { depth with brace := depth.brace + 1 }
  | .closeBrace => { depth with brace := depth.brace - 1 }
  | .templateStart => { depth with template := depth.template + 1 }
  | .templateEnd => { depth with template := depth.template - 1 }
  | _ => depth

inductive AngleStep where
  | eof
  | closed
  | advance (angles : Int) (depth : GroupDepth)

def angleStep (kind : Kind) (angles : Int) (depth : GroupDepth) : AngleStep :=
  if kind == .eof then .eof
  else if depth.isNested then .advance angles (depth.step kind)
  else match kind with
    | .openAngle => .advance (angles + 1) depth
    | .closeAngle => if angles == 1 then .closed else .advance (angles - 1) depth
    | _ => .advance angles (depth.step kind)

def skipAngles (input : Input) (index : Nat) (angles : Int) (depth : GroupDepth) : Nat → Nat
  | 0 => index
  | n + 1 =>
    match angleStep (input.get index).kind angles depth with
    | .eof => index
    | .closed => index + 1
    | .advance angles depth => skipAngles input (index + 1) angles depth n

def offsetPastAngles (input : Input) (start : Nat) : Nat :=
  skipAngles input start 0 {} (input.count - start + 1)

theorem skipAnglesStopsAtOuterClose
    (close : (input.get index).kind = .closeAngle) :
    skipAngles input index 1 {} (fuel + 1) = index + 1 := by
  simp [skipAngles, angleStep, close, GroupDepth.isNested]

theorem skipAnglesIgnoresCloseInExpressionGroup
    (close : (input.get index).kind = .closeAngle) (nested : depth.isNested = true) :
    skipAngles input index angles depth (fuel + 1) =
      skipAngles input (index + 1) angles depth fuel := by
  simp [skipAngles, angleStep, close, nested, GroupDepth.step]

theorem skipAnglesContinuesPastInnerClose
    (close : (input.get index).kind = .closeAngle)
    (outerExpression : depth.isNested = false) (innerAngles : angles ≠ 1) :
    skipAngles input index angles depth (fuel + 1) =
      skipAngles input (index + 1) (angles - 1) depth fuel := by
  simp [skipAngles, angleStep, close, outerExpression, innerAngles]

theorem skipAnglesLeavesEOF (eof : (input.get index).kind = .eof) :
    skipAngles input index angles depth (fuel + 1) = index := by
  simp [skipAngles, angleStep, eof]

inductive AngleScanPath (input : Input) :
    Nat → Int → GroupDepth → Nat → Int → GroupDepth → Prop where
  | empty : AngleScanPath input index angles depth 0 angles depth
  | next (step : angleStep (input.get index).kind angles depth = .advance nextAngles nextDepth)
      (rest : AngleScanPath input (index + 1) nextAngles nextDepth steps lastAngles lastDepth) :
      AngleScanPath input index angles depth (steps + 1) lastAngles lastDepth

theorem skipAnglesThroughPath
    (path : AngleScanPath input index angles depth steps lastAngles lastDepth) :
    skipAngles input index angles depth (steps + work) =
      skipAngles input (index + steps) lastAngles lastDepth work := by
  induction path with
  | empty => simp
  | @next index angles depth nextAngles nextDepth steps lastAngles lastDepth step rest ih =>
    simpa [Nat.add_right_comm steps 1 work, Nat.add_right_comm index 1 steps, skipAngles, step] using ih

theorem skipAnglesDoesNotPassEOF
    (input : Input) (eofIndex : Nat) (eof : (input.get eofIndex).kind = .eof)
    (fuel index : Nat) (angles : Int) (depth : GroupDepth) (before : index ≤ eofIndex) :
    skipAngles input index angles depth fuel ≤ eofIndex := by
  induction fuel generalizing index angles depth with
  | zero => simpa [skipAngles] using before
  | succ fuel ih =>
    rcases Nat.eq_or_lt_of_le before with equal | earlier
    · cases equal
      simp [skipAngles, angleStep, eof]
    · cases step : angleStep (input.get index).kind angles depth with
      | eof => simpa [skipAngles, step] using before
      | closed => simpa [skipAngles, step] using (Nat.succ_le_of_lt earlier)
      | advance nextAngles nextDepth =>
        simpa [skipAngles, step] using ih (index + 1) nextAngles nextDepth (Nat.succ_le_of_lt earlier)

def skipParens (input : Input) (origin index depth : Nat) (limited : Bool) : Nat → Nat
  | 0 => if limited then origin else index
  | n + 1 =>
    match (input.get index).kind with
    | .eof => index
    | .openParen => skipParens input origin (index + 1) (depth + 1) limited n
    | .closeParen =>
      if depth ≤ 1 then index + 1 else skipParens input origin (index + 1) (depth - 1) limited n
    | _ =>
      if depth == 0 then index + 1 else skipParens input origin (index + 1) depth limited n

def offsetPastParens (input : Input) (start : Nat) (limit : Option Nat) : Nat :=
  let fuel := input.count - start + 1
  match limit with
  | none => skipParens input start start 0 false fuel
  | some maxDistance => skipParens input start start 0 true (min fuel maxDistance)

theorem skipParensStopsAtOuterClose
    (close : (input.get index).kind = .closeParen) :
    skipParens input origin index 1 limited (fuel + 1) = index + 1 := by
  simp [skipParens, close]

theorem skipParensLeavesEOF (eof : (input.get index).kind = .eof) :
    skipParens input origin index depth limited (fuel + 1) = index := by
  simp [skipParens, eof]

theorem skipParensContinuesPastInnerClose
    (close : (input.get index).kind = .closeParen) (inner : 1 < depth) :
    skipParens input origin index depth limited (fuel + 1) =
      skipParens input origin (index + 1) (depth - 1) limited fuel := by
  have notOuter := Nat.not_le.mpr inner
  simp [skipParens, close, notOuter]

theorem skipParensReturnsOriginAtLimit :
    skipParens input origin index depth true 0 = origin := rfl

end TypeArguments.FFI
