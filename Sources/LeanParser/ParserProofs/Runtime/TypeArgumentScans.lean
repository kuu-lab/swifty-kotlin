import ParserProofs.Runtime.ParameterPrefixes

set_option warningAsError true

namespace TypeArguments.FFI

def skipAnnotations (input : Input) (index : Nat) : Nat → Option Nat × Option Nat
  | 0 =>
    if (input.get index).kind == .at then (none, some index) else (some index, none)
  | n + 1 =>
    if (input.get index).kind != .at then (some index, none)
    else match annotationTail input (index + 1) with
      | some next => skipAnnotations input next n
      | none => (none, none)

inductive AnnotationListPath (input : Input) : Nat → Nat → Nat → Prop where
  | empty : AnnotationListPath input index index 0
  | next (atSign : (input.get index).kind = .at)
      (tail : annotationTail input (index + 1) = some nextIndex)
      (rest : AnnotationListPath input nextIndex last steps) :
      AnnotationListPath input index last (steps + 1)

theorem skipAnnotationsThroughPath (path : AnnotationListPath input index last steps) :
    skipAnnotations input index (steps + fuel) = skipAnnotations input last fuel := by
  induction path with
  | empty => simp
  | @next index nextIndex last steps atSign tail rest ih =>
    simpa [Nat.add_right_comm steps 1 fuel, skipAnnotations, atSign, tail] using ih

theorem skipAnnotationsStopsAtFirstNonAnnotation
    (path : AnnotationListPath input index last steps)
    (notAnnotation : (input.get last).kind ≠ .at) :
    skipAnnotations input index (steps + fuel) = (some last, none) := by
  rw [skipAnnotationsThroughPath path]
  cases fuel <;> simp [skipAnnotations, notAnnotation]

def enumEntryNameAt (input : Input) (index : Nat) : Bool :=
  let token := input.get index
  token.kind != .eof && token.kind != .context && token.identifierLike &&
    !isDeclarationStart input index token.kind

def enumEntryAfterAnnotations (input : Input) (start : Nat) : Bool :=
  (input.get start).kind == .at &&
    (skipAnnotations input start (input.count - start + 1)).1.any (enumEntryNameAt input)

theorem enumEntryAfterAnnotationsUsesFirstNonAnnotation
    (atSign : (input.get start).kind = .at)
    (path : AnnotationListPath input start last steps)
    (notAnnotation : (input.get last).kind ≠ .at)
    (enough : steps ≤ input.count - start + 1) :
    enumEntryAfterAnnotations input start = enumEntryNameAt input last := by
  have fuel : input.count - start + 1 = steps + (input.count - start + 1 - steps) := by omega
  unfold enumEntryAfterAnnotations
  rw [fuel, skipAnnotationsStopsAtFirstNonAnnotation path notAnnotation]
  simp [atSign]

theorem enumEntryRejectsMissingAnnotationName
    (path : AnnotationListPath input start index steps)
    (atSign : (input.get index).kind = .at)
    (missing : (input.get (annotationName input (index + 1))).identifierLike = false)
    (enough : steps < input.count - start + 1) :
    enumEntryAfterAnnotations input start = false := by
  have fuel : input.count - start + 1 = steps + (input.count - start - steps + 1) := by omega
  unfold enumEntryAfterAnnotations
  rw [fuel, skipAnnotationsThroughPath path]
  simp [skipAnnotations, atSign, annotationTailRequiresName missing]

theorem enumEntryRejectsAnnotationListEndingAtEOF
    (atSign : (input.get start).kind = .at)
    (path : AnnotationListPath input start last steps)
    (enough : steps ≤ input.count - start + 1)
    (eof : (input.get last).kind = .eof) :
    enumEntryAfterAnnotations input start = false := by
  rw [enumEntryAfterAnnotationsUsesFirstNonAnnotation atSign path (by simp [eof]) enough]
  simp [enumEntryNameAt, eof]

theorem enumEntryRejectsAnnotationTailReachingEOF
    (first : (input.get start).kind = .at)
    (path : AnnotationListPath input start index steps)
    (atSign : (input.get index).kind = .at)
    (tail : annotationTail input (index + 1) = some endIndex)
    (eof : (input.get endIndex).kind = .eof)
    (enough : steps < input.count - start + 1) :
    enumEntryAfterAnnotations input start = false := by
  have fuel : input.count - start + 1 = steps + (input.count - start - steps + 1) := by omega
  have stopped : skipAnnotations input endIndex (input.count - start - steps) = (some endIndex, none) := by
    cases input.count - start - steps <;> simp [skipAnnotations, eof]
  unfold enumEntryAfterAnnotations
  rw [fuel, skipAnnotationsThroughPath path]
  simp [first, skipAnnotations, atSign, tail, stopped, enumEntryNameAt, eof]

inductive ConstructorPrefixStep where
  | advance (nextIndex : Nat)
  | terminal
  | incomplete

def constructorPrefixStep (input : Input) (index : Nat) : ConstructorPrefixStep :=
  match (input.get index).kind with
  | .modifier => .advance (index + 1)
  | .at =>
    match annotationTail input (index + 1) with
    | some next => .advance next
    | none => .incomplete
  | _ => .terminal

def scanConstructorPrefix (input : Input) (index : Nat) : Nat → Option Nat
  | 0 => none
  | work + 1 =>
    match constructorPrefixStep input index with
    | .advance next => scanConstructorPrefix input next work
    | .terminal => some index
    | .incomplete => none

def constructorHeaderAt (input : Input) (index : Nat) : Bool :=
  let token := input.get index
  token.kind != .eof && token.constructorKeyword && (input.get (index + 1)).kind == .openParen

def startsPrimaryConstructorHeader (input : Input) (start : Nat) : Bool :=
  (scanConstructorPrefix input start (input.count - start + 1)).any (constructorHeaderAt input)

inductive ConstructorPrefixPath (input : Input) : Nat → Nat → Nat → Prop where
  | empty : ConstructorPrefixPath input index index 0
  | next (advance : constructorPrefixStep input index = .advance nextIndex)
      (rest : ConstructorPrefixPath input nextIndex last steps) :
      ConstructorPrefixPath input index last (steps + 1)

theorem scanConstructorPrefixThroughPath (path : ConstructorPrefixPath input start last steps) :
    scanConstructorPrefix input start (steps + work) = scanConstructorPrefix input last work := by
  induction path with
  | empty => simp
  | @next index nextIndex last steps advance rest ih =>
    simpa [Nat.add_right_comm steps 1 work, scanConstructorPrefix, advance] using ih

theorem scanConstructorPrefixStopsAtFirstNonPrefix
    (path : ConstructorPrefixPath input start last steps)
    (notAnnotation : (input.get last).kind ≠ .at)
    (notModifier : (input.get last).kind ≠ .modifier) :
    scanConstructorPrefix input start (steps + (work + 1)) = some last := by
  rw [scanConstructorPrefixThroughPath path]
  generalize kindEq : (input.get last).kind = kind at notAnnotation notModifier ⊢
  cases kind <;> simp_all [scanConstructorPrefix, constructorPrefixStep]

theorem primaryConstructorHeaderAtFirstNonPrefixIff
    (path : ConstructorPrefixPath input start last steps)
    (notAnnotation : (input.get last).kind ≠ .at)
    (notModifier : (input.get last).kind ≠ .modifier)
    (notEOF : (input.get last).kind ≠ .eof)
    (enough : steps < input.count - start + 1) :
    startsPrimaryConstructorHeader input start = true ↔
      (input.get last).constructorKeyword = true ∧ (input.get (last + 1)).kind = .openParen := by
  have fuel : input.count - start + 1 = steps + (input.count - start - steps + 1) := by omega
  unfold startsPrimaryConstructorHeader
  rw [fuel, scanConstructorPrefixStopsAtFirstNonPrefix path notAnnotation notModifier]
  simp [constructorHeaderAt, notEOF]

theorem primaryConstructorRejectsMissingAnnotationName
    (path : ConstructorPrefixPath input start index steps)
    (atSign : (input.get index).kind = .at)
    (missing : (input.get (annotationName input (index + 1))).identifierLike = false)
    (enough : steps < input.count - start + 1) :
    startsPrimaryConstructorHeader input start = false := by
  have fuel : input.count - start + 1 = steps + (input.count - start - steps + 1) := by omega
  unfold startsPrimaryConstructorHeader
  rw [fuel, scanConstructorPrefixThroughPath path]
  simp [scanConstructorPrefix, constructorPrefixStep, atSign, annotationTailRequiresName missing]

theorem primaryConstructorRejectsAnnotationTailReachingEOF
    (path : ConstructorPrefixPath input start index steps)
    (atSign : (input.get index).kind = .at)
    (tail : annotationTail input (index + 1) = some endIndex)
    (eof : (input.get endIndex).kind = .eof)
    (enough : steps < input.count - start + 1) :
    startsPrimaryConstructorHeader input start = false := by
  have fuel : input.count - start + 1 = steps + (input.count - start - steps + 1) := by omega
  unfold startsPrimaryConstructorHeader
  rw [fuel, scanConstructorPrefixThroughPath path]
  simp only [scanConstructorPrefix, constructorPrefixStep, atSign, tail]
  cases input.count - start - steps <;> simp [scanConstructorPrefix, constructorPrefixStep, constructorHeaderAt, eof]

def annotationContinues (input : Input) (index : Nat) : Bool :=
  let token := input.get index
  if token.kind == .context then !isDeclarationStart input index token.kind
  else !isDeclarationStart input index token.kind && (token.identifierLike || token.kind == .varianceIn)

def checkBoundary (input : Input) (workLimit index : Nat) (token : LexToken)
    (effects : Effects) : Bool × Effects :=
  if !token.newline then (false, effects) else
    match token.kind with
    | .at =>
      let (after, budgetAt) := skipAnnotations input index workLimit
      (!(after.any (annotationContinues input)), { effects with budgetAt := budgetAt })
    | .context => (isDeclarationStart input index token.kind, effects)
    | .modifier =>
      match effects.runs.head? with
      | some run =>
        if index < run.endIndex then (run.declares, effects)
        else newModifierLookahead
      | none => newModifierLookahead
    | .declaration | .funKeyword | .objectKeyword => (true, effects)
    | _ => (false, effects)
where
  newModifierLookahead :=
    let (declares, endIndex, budgetAt) := modifierLookahead input index workLimit true
    let runs := if endIndex > index then ⟨index, endIndex, declares⟩ :: effects.runs else effects.runs
    (declares, { runs, budgetAt })

def projectThroughStop (input : Input) (workLimit index depth : Nat)
    (reversed : List Token) (effects : Effects) : Nat → List Token × Effects
  | 0 => (reversed.reverse, effects)
  | fuel + 1 =>
    let token := input.get index
    let (projected, effects) : Token × Effects := match token.kind with
      | .eof => (.eof, effects)
      | .openAngle => (.openAngle, effects)
      | .closeAngle => (.closeAngle, effects)
      | _ =>
        let (boundary, effects) := if depth == 0 then checkBoundary input workLimit index token effects
                                  else (false, effects)
        (if boundary then .boundary else .other, effects)
    match ParserProofs.TypeArgumentConsumption.projectionNext projected depth with
    | none => ((projected :: reversed).reverse, effects)
    | some nextDepth =>
      projectThroughStop input workLimit (index + 1) nextDepth (projected :: reversed) effects fuel


def isVariance : Kind → Bool
  | .varianceIn | .varianceOut => true
  | _ => false

def canStartLookahead (input : Input) (index nested : Nat)
    (expected sawProjection previousVariance : Bool) : Nat → Bool
  | 0 => false
  | fuel + 1 =>
    let kind := (input.get index).kind
    match kind with
    | .eof => nested == 0 && sawProjection && !expected
    | .openAngle => canStartLookahead input (index + 1) (nested + 1) expected sawProjection false fuel
    | .closeAngle =>
      if nested == 0 then sawProjection && !previousVariance
      else canStartLookahead input (index + 1) (nested - 1) expected sawProjection false fuel
    | _ =>
      let variance := isVariance kind
      if nested != 0 then
        canStartLookahead input (index + 1) nested expected sawProjection variance fuel
      else match kind with
        | .comma =>
          sawProjection && !expected &&
            canStartLookahead input (index + 1) nested true sawProjection false fuel
        | .identifier | .star =>
          canStartLookahead input (index + 1) nested false true false fuel
        | .varianceIn | .varianceOut =>
          canStartLookahead input (index + 1) nested true sawProjection true fuel
        | .dot | .question | .questionDot | .doubleColon | .colon =>
          !expected && canStartLookahead input (index + 1) nested expected sawProjection false fuel
        | _ => canStartLookahead input (index + 1) nested expected sawProjection false fuel
termination_by structural fuel => fuel

def canStart (input : Input) (start : Nat) (hasAnchor : Bool) : Bool :=
  hasAnchor && (input.get start).kind == .openAngle &&
    canStartLookahead input (start + 1) 0 true false false (input.count - start + 1)

theorem canStartAcceptsOuterTrailingComma
    (comma : (input.get index).kind = .comma)
    (close : (input.get (index + 1)).kind = .closeAngle) :
    canStartLookahead input index 0 false true previousVariance (fuel + 2) = true := by
  simp [canStartLookahead, comma, close]

theorem canStartRejectsEmptyList
    (opening : (input.get start).kind = .openAngle)
    (close : (input.get (start + 1)).kind = .closeAngle) :
    canStart input start hasAnchor = false := by
  simp [canStart, canStartLookahead, opening, close]

theorem canStartRejectsOuterConsecutiveCommas
    (first : (input.get index).kind = .comma)
    (second : (input.get (index + 1)).kind = .comma) :
    canStartLookahead input index 0 expected sawProjection previousVariance (fuel + 2) = false := by
  simp [canStartLookahead, first, second]

theorem canStartRejectsOuterDanglingVariance
    (variance : (input.get index).kind = .varianceIn ∨ (input.get index).kind = .varianceOut)
    (close : (input.get (index + 1)).kind = .closeAngle) :
    canStartLookahead input index 0 expected sawProjection previousVariance (fuel + 2) = false := by
  rcases variance with variance | variance <;> simp [canStartLookahead, variance, close]

def defaultArgumentClose (input : Input) (index : Nat) (depth : Int) : Nat → Option Nat
  | 0 => none
  | fuel + 1 =>
    match (input.get index).kind with
    | .eof => none
    | .openAngle => defaultArgumentClose input (index + 1) (depth + 1) fuel
    | .closeAngle =>
      if depth == 1 then some (index + 1)
      else defaultArgumentClose input (index + 1) (depth - 1) fuel
    | _ => defaultArgumentClose input (index + 1) depth fuel

def defaultStartsTypeArguments (input : Input) (start : Nat) (anchored : Bool) : Bool :=
  anchored && (defaultArgumentClose input start 0 4096).any fun next =>
    ((input.get next).kind == .openParen || (input.get next).kind == .openBrace) &&
      canStart input start true

theorem defaultArgumentCloseRejectsAtLimit :
    defaultArgumentClose input index depth 0 = none := rfl

theorem defaultArgumentCloseStopsAtOuterClose
    (close : (input.get index).kind = .closeAngle) :
    defaultArgumentClose input index 1 (fuel + 1) = some (index + 1) := by
  simp [defaultArgumentClose, close]

theorem defaultStartsRequiresCallOrLambda
    (accepted : defaultStartsTypeArguments input start anchored = true) :
    anchored = true ∧ canStart input start true = true ∧
      ∃ next, defaultArgumentClose input start 0 4096 = some next ∧
        ((input.get next).kind = .openParen ∨ (input.get next).kind = .openBrace) := by
  unfold defaultStartsTypeArguments at accepted
  cases close : defaultArgumentClose input start 0 4096 with
  | none => simp [close] at accepted
  | some next =>
    have parts : anchored = true ∧
        (((input.get next).kind = .openParen ∨ (input.get next).kind = .openBrace) ∧
          canStart input start true = true) := by
      simpa [close, Bool.and_assoc] using accepted
    exact ⟨parts.1, parts.2.2, next, rfl, parts.2.1⟩

def parenthesizedReceiverHasName (input : Input) (start : Nat) : Bool :=
  let endIndex := offsetPastParens input start (some 4096)
  let separator := if (input.get endIndex).kind == .question then endIndex + 1 else endIndex
  ((input.get separator).kind == .dot || (input.get separator).kind == .questionDot) &&
    (input.get (separator + 1)).identifierLike

def anonymousFunctionLookahead (input : Input) (index : Nat) (depth : Int)
    (previous : Kind) : Nat → Bool
  | 0 => false
  | fuel + 1 =>
    let kind := (input.get index).kind
    match kind with
    | .eof => false
    | .openParen =>
      if depth == 0 then
        match previous with
        | .funKeyword | .closeAngle => !parenthesizedReceiverHasName input index
        | .dot | .questionDot => true
        | _ => false
      else anonymousFunctionLookahead input (index + 1) (depth + 1) kind fuel
    | .openBracket | .openAngle =>
      anonymousFunctionLookahead input (index + 1) (depth + 1) kind fuel
    | .closeParen | .closeBracket | .closeAngle =>
      anonymousFunctionLookahead input (index + 1) (depth - 1) kind fuel
    | .openBrace | .closeBrace | .semicolon | .assign =>
      depth != 0 && anonymousFunctionLookahead input (index + 1) depth kind fuel
    | _ => anonymousFunctionLookahead input (index + 1) depth kind fuel
termination_by structural fuel => fuel

def anonymousFunctionAt (input : Input) (index : Nat) : Bool :=
  (input.get index).kind == .funKeyword &&
    anonymousFunctionLookahead input (index + 1) 0 .funKeyword 199

theorem anonymousFunctionRequiresFun
    (accepted : anonymousFunctionAt input index = true) :
    (input.get index).kind = .funKeyword := by
  simp [anonymousFunctionAt] at accepted
  exact accepted.1

theorem anonymousFunctionRejectsNamedReceiver
    (opening : (input.get index).kind = .openParen)
    (named : parenthesizedReceiverHasName input index = true)
    (head : previous = .funKeyword ∨ previous = .closeAngle) :
    anonymousFunctionLookahead input index 0 previous (fuel + 1) = false := by
  rcases head with rfl | rfl <;> simp [anonymousFunctionLookahead, opening, named]

theorem anonymousFunctionAcceptsUnnamedParameters
    (opening : (input.get index).kind = .openParen)
    (unnamed : parenthesizedReceiverHasName input index = false) :
    anonymousFunctionLookahead input index 0 .funKeyword (fuel + 1) = true := by
  simp [anonymousFunctionLookahead, opening, unnamed]

theorem anonymousFunctionStopsAtOuterTerminator
    (terminal : (input.get index).kind = .openBrace ∨ (input.get index).kind = .closeBrace ∨
      (input.get index).kind = .semicolon ∨ (input.get index).kind = .assign) :
    anonymousFunctionLookahead input index 0 previous (fuel + 1) = false := by
  rcases terminal with kind | kind | kind | kind <;> simp [anonymousFunctionLookahead, kind]

def decodeKind : UInt8 → Kind
  | 1 => .openAngle | 2 => .closeAngle | 3 => .at | 4 => .dot | 5 => .colon
  | 6 => .openParen | 7 => .closeParen | 8 => .openBracket | 9 => .closeBracket
  | 10 => .openBrace | 11 => .closeBrace | 12 => .templateStart | 13 => .templateEnd
  | 14 => .context | 15 => .modifier | 16 => .declaration | 17 => .varianceIn | 18 => .eof
  | 19 => .identifier | 20 => .star | 21 => .varianceOut | 22 => .comma
  | 23 => .question | 24 => .questionDot | 25 => .doubleColon
  | 26 => .assign | 27 => .funKeyword | 28 => .objectKeyword | 29 => .semicolon
  | 30 => .bang | 31 => .bangBang | 32 => .isKeyword | 33 => .literal | 34 => .expressionKeyword
  | 35 => .plus | 36 => .minus | 37 => .stringStart
  | 38 => .catchKeyword | 39 => .finallyKeyword | 40 => .elseKeyword | 41 => .asKeyword
  | 42 => .byKeyword | 43 => .slash | 44 => .percent | 45 => .ampAmp
  | 46 => .barBar | 47 => .equalEqual | 48 => .bangEqual | 49 => .tripleEqual
  | 50 => .notTripleEqual | 51 => .lessOrEqual | 52 => .greaterOrEqual | 53 => .plusAssign
  | 54 => .minusAssign | 55 => .starAssign | 56 => .slashAssign | 57 => .percentAssign
  | 58 => .dotDot | 59 => .dotDotLt | 60 => .questionQuestion | 61 => .questionColon
  | 62 => .arrow | 63 => .enumKeyword | 64 => .importKeyword
  | 65 => .returnKeyword | 66 => .companionKeyword | 67 => .packageKeyword
  | 68 => .classKeyword | 69 => .interfaceKeyword | 70 => .propertyKeyword
  | 71 => .typeAliasKeyword | 72 => .constructorKeyword | 73 => .accessorKeyword
  | 74 => .loopKeyword | 75 => .whenKeyword | 76 => .softWhenKeyword | 77 => .companionNameKeyword
  | 78 => .whereKeyword | 79 => .constructorDelegationKeyword | 80 => .nonToken
  | _ => .other

@[extern "kswiftk_lean_read_token"]
opaque readToken (context index : USize) : UInt32

@[extern "kswiftk_lean_record_cache"]
opaque recordCache (context start endIndex : USize) (declares : UInt8) : IO Unit

@[extern "kswiftk_lean_report_budget"]
opaque reportBudget (context index : USize) : IO Unit

@[extern "kswiftk_lean_parse_file_item"]
opaque parseFileItem (context : USize) (dispatch : UInt8) : IO UInt64

@[extern "kswiftk_lean_emit_file_item"]
opaque emitFileItem (context : USize) (action : UInt8) (separators : USize) : IO USize

def decodeToken (raw : UInt32) : LexToken :=
  ⟨decodeKind raw.toUInt8, raw &&& 256 != 0, raw &&& 512 != 0, raw &&& 1024 != 0,
    if raw &&& 2048 != 0 then some (raw &&& 4096 != 0) else none,
    raw &&& 8192 != 0, raw &&& 16384 != 0, raw &&& 32768 != 0, raw &&& 65536 != 0,
    raw &&& 131072 != 0, raw &&& 262144 != 0, raw &&& 524288 != 0, raw &&& 1048576 != 0,
    if raw &&& 2097152 != 0 then some (raw &&& 4194304 != 0) else none,
    raw &&& 8388608 != 0, raw &&& 16777216 != 0, raw &&& 33554432 != 0,
    raw &&& 67108864 != 0, raw &&& 134217728 != 0, raw &&& 268435456 != 0,
    raw &&& 536870912 != 0, raw &&& 1073741824 != 0⟩

def callbackInput (context count : USize) : Input :=
  ⟨count.toNat, fun index => decodeToken (readToken context index.toUSize)⟩

@[export kswiftk_lean_can_start_type_arguments]
def canStartFrom (context count start : USize) (hasAnchor : UInt8) : UInt8 :=
  if canStart (callbackInput context count) start.toNat (hasAnchor != 0) then 1 else 0

@[export kswiftk_lean_type_arguments]
def scanFrom (context count start : USize) (workLimit : UInt32) : IO UInt64 := do
  let input := callbackInput context count
  if (input.get start.toNat).kind != .openAngle then return 0
  let (tokens, effects) := projectThroughStop input workLimit.toNat (start.toNat + 1) 0
    [.openAngle] {} (input.count - start.toNat + 1)
  for run in effects.runs.reverse do
    recordCache context run.start.toUSize run.endIndex.toUSize (if run.declares then 1 else 0)
  if let some index := effects.budgetAt then
    reportBudget context index.toUSize
  let result := TypeArguments.parse tokens
  let stop : Nat := match result.stop with
    | .missingOpen => 0 | .closed => 1 | .recovery => 2 | .eof => 3
  return ((tokens.length - result.remaining.length) * 4 + stop).toUInt64

end TypeArguments.FFI
