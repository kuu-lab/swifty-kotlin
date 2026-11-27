import ParserProofs.Runtime.FileLoop

set_option warningAsError true

namespace TypeArguments.FFI

def scanAccessorModifiers (input : Input) (index : Nat) (visibility : Bool) : Nat → Nat × Bool
  | 0 => (index, visibility)
  | work + 1 =>
    let token := input.get index
    if token.visibilityModifier || token.inlineModifier then
      scanAccessorModifiers input (index + 1) (visibility || token.visibilityModifier) work
    else (index, visibility)

def accessorPrefixesAt (input : Input) (start : Nat) : Option (Nat × Bool) :=
  (skipAnnotations input start (input.count - start + 1)).1.map fun index =>
    scanAccessorModifiers input index false (input.count - index + 1)

def isAccessorBodyToken (kind : Kind) : Bool :=
  kind == .assign || kind == .openBrace

inductive AccessorTypeStep where
  | found
  | rejected
  | advance (probeDeclaration : Bool)

def accessorTypeStep (token : LexToken) (depth : WhenSubjectTypeDepth) (sawType : Bool) : AccessorTypeStep :=
  if token.kind == .eof then .rejected
  else if depth.isTopLevel then
    if isAccessorBodyToken token.kind then .found
    else if token.kind == .semicolon || token.kind == .closeBrace then .rejected
    else .advance (sawType && token.newline)
  else .advance false

def accessorTypeHasBody (input : Input) (declarationAt : Nat → IO Bool) (index : Nat)
    (depth : WhenSubjectTypeDepth) (sawType : Bool) : Nat → IO Bool
  | 0 => pure false
  | work + 1 => do
    let token := input.get index
    match accessorTypeStep token depth sawType with
    | .found => return true
    | .rejected => return false
    | .advance probe =>
      let stops ← if probe then declarationAt index else pure false
      if stops then return false
      accessorTypeHasBody input declarationAt (index + 1) (depth.step token.kind) true work

def accessorHasBody (input : Input) (declarationAt : Nat → IO Bool) (index : Nat) : IO Bool := do
  if (input.get (index + 1)).kind != .openParen then return false
  let some after := accessorParameterEnd input (index + 2) 1 63 | return false
  if (input.get after).kind != .colon then return isAccessorBodyToken (input.get after).kind
  accessorTypeHasBody input declarationAt (after + 1) {} false (index + 64 - after)

def endsBodylessAccessor (token : LexToken) : Bool :=
  token.kind == .eof || token.kind == .semicolon || token.kind == .closeBrace || token.newline

def acceptsAccessor (token follower : LexToken) (allowsBodyless visibility hasBody : Bool) : Bool :=
  isAccessorKeyword token &&
    (hasBody || ((allowsBodyless || (visibility && token.setterKeyword)) && endsBodylessAccessor follower))

def isPropertyAccessorStart (input : Input) (declarationAt : Nat → IO Bool)
    (start : Nat) (allowsBodyless : Bool) : IO Bool := do
  let some (index, visibility) := accessorPrefixesAt input start | return false
  let token := input.get index
  if !isAccessorKeyword token then return false
  let hasBody ← accessorHasBody input declarationAt index
  return acceptsAccessor token (input.get (index + 1)) allowsBodyless visibility hasBody

theorem accessorModifiersContinueAndRecordVisibility
    (modifier : ((input.get index).visibilityModifier || (input.get index).inlineModifier) = true) :
    scanAccessorModifiers input index visibility (work + 1) =
      scanAccessorModifiers input (index + 1) (visibility || (input.get index).visibilityModifier) work := by
  simp [scanAccessorModifiers, modifier]

theorem accessorModifiersStopAtFirstOtherToken
    (other : ((input.get index).visibilityModifier || (input.get index).inlineModifier) = false) :
    scanAccessorModifiers input index visibility work = (index, visibility) := by
  cases work <;> simp [scanAccessorModifiers, other]

theorem accessorPrefixesSkipLeadingAnnotations
    (path : AnnotationListPath input start last steps)
    (notAnnotation : (input.get last).kind ≠ .at)
    (enough : steps ≤ input.count - start + 1) :
    accessorPrefixesAt input start =
      some (scanAccessorModifiers input last false (input.count - last + 1)) := by
  have fuel : input.count - start + 1 = steps + (input.count - start + 1 - steps) := by omega
  unfold accessorPrefixesAt
  rw [fuel, skipAnnotationsStopsAtFirstNonAnnotation path notAnnotation]
  simp

theorem propertyAccessorRejectsMissingAnnotationName
    (path : AnnotationListPath input start index steps)
    (atSign : (input.get index).kind = .at)
    (missing : (input.get (annotationName input (index + 1))).identifierLike = false)
    (enough : steps < input.count - start + 1) :
    isPropertyAccessorStart input declarationAt start allowsBodyless = pure false := by
  have fuel : input.count - start + 1 = steps + (input.count - start - steps + 1) := by omega
  unfold isPropertyAccessorStart accessorPrefixesAt
  rw [fuel, skipAnnotationsThroughPath path]
  simp [skipAnnotations, atSign, annotationTailRequiresName missing]

theorem propertyAccessorRejectsAnnotationListEndingAtEOF
    (path : AnnotationListPath input start last steps)
    (eof : (input.get last).kind = .eof)
    (notModifier : ((input.get last).visibilityModifier || (input.get last).inlineModifier) = false)
    (enough : steps ≤ input.count - start + 1) :
    isPropertyAccessorStart input declarationAt start allowsBodyless = pure false := by
  unfold isPropertyAccessorStart
  rw [accessorPrefixesSkipLeadingAnnotations path (by simp [eof]) enough,
    accessorModifiersStopAtFirstOtherToken notModifier]
  simp [isAccessorKeyword, eof]

theorem accessorBodyAcceptsGetterOrSetter :
    acceptsAccessor token follower allowsBodyless visibility true = isAccessorKeyword token := by
  simp [acceptsAccessor]

theorem bodylessAccessorFollowerIff :
    endsBodylessAccessor token = true ↔
      token.kind = .eof ∨ token.kind = .semicolon ∨ token.kind = .closeBrace ∨ token.newline = true := by
  simp [endsBodylessAccessor, or_assoc]

theorem bodylessAccessorAcceptedIff :
    acceptsAccessor token follower allowsBodyless visibility false = true ↔
      isAccessorKeyword token = true ∧
        (allowsBodyless = true ∨ (visibility = true ∧ token.setterKeyword = true)) ∧
        endsBodylessAccessor follower = true := by
  simp [acceptsAccessor, and_assoc]

theorem localBodylessAccessorRequiresVisibleSetter
    (accessor : isAccessorKeyword token = true) :
    acceptsAccessor token follower false visibility false = true ↔
      visibility = true ∧ token.setterKeyword = true ∧ endsBodylessAccessor follower = true := by
  simp [bodylessAccessorAcceptedIff, accessor, and_assoc]

theorem accessorParametersStopAtOuterClose
    (close : (input.get index).kind = .closeParen) :
    accessorParameterEnd input index 1 (work + 1) = some (index + 1) := by
  simp [accessorParameterEnd, accessorParameterStep, close]

theorem accessorTypeFindsBodyMarkerAtTopLevel
    (top : depth.isTopLevel = true) (marker : token.kind = .assign ∨ token.kind = .openBrace) :
    accessorTypeStep token depth sawType = .found := by
  rcases marker with kind | kind <;> simp [accessorTypeStep, top, kind, isAccessorBodyToken]

theorem accessorHeaderAcceptsDirectBody
    (opening : (input.get (index + 1)).kind = .openParen)
    (parameters : accessorParameterEnd input (index + 2) 1 63 = some after)
    (marker : (input.get after).kind = .assign ∨ (input.get after).kind = .openBrace) :
    accessorHasBody input declarationAt index = pure true := by
  rcases marker with kind | kind <;>
    simp [accessorHasBody, opening, parameters, isAccessorBodyToken, kind] <;> rfl

theorem accessorTypeScanStopsAtDeclaration
    (step : accessorTypeStep (input.get index) depth sawType = .advance true)
    (declares : declarationAt index = pure true) :
    accessorTypeHasBody input declarationAt index depth sawType (work + 1) = pure false := by
  simp [accessorTypeHasBody, step, declares]
  rfl

@[export kswiftk_lean_property_accessor]
def propertyAccessorFrom (context count start : USize) (allowsBodyless : UInt8) (workLimit : UInt32) :
    IO UInt64 := do
  let input := callbackInput context count
  let declarationAt := fun index => do
    return (← runGenuineDeclarationAt context input index workLimit.toNat) != .notDeclaration
  let accepts ← isPropertyAccessorStart input declarationAt start.toNat (allowsBodyless != 0)
  return if accepts then 1 else 0

def applyDeclarationEffect (context : USize) : DeclarationEffect → IO Unit
  | .budget index => reportBudget context index.toUSize
  | .cache run =>
    recordCache context run.start.toUSize run.endIndex.toUSize (if run.declares then 1 else 0)

def runLikelyDeclarationAt (context : USize) (input : Input) (index workLimit : Nat) : IO Bool := do
  let (declares, effects) := likelyDeclarationAt input index workLimit
  for effect in effects do
    applyDeclarationEffect context effect
  return declares

def runValueParameterPrefixAt (context : USize) (input : Input) (index workLimit : Nat) :
    IO (Option Nat) := do
  match valueParameterPrefixLookahead input index false workLimit with
  | .found endIndex => return some endIndex
  | .rejected => return none
  | .budget position =>
    reportBudget context position.toUSize
    return none

def runWhenSubjectPrefixAt (context : USize) (input : Input) (index workLimit : Nat) :
    IO (Option Nat) := do
  let (result, effectsRev) := whenSubjectPrefixLookahead input index workLimit
  for effect in effectsRev.reverse do
    applyDeclarationEffect context effect
  match result with
  | .found assignIndex => return some assignIndex
  | .rejected | .declarationBoundary => return none
  | .budget position =>
    reportBudget context position.toUSize
    return none

@[export kswiftk_lean_balanced_group]
def scanGroupFrom (context count start : USize) (opening closing options : UInt8)
    (workLimit : UInt32) : IO UInt64 := do
  let input := callbackInput context count
  let queries : GroupQueries := {
    declarationAt := fun index => runLikelyDeclarationAt context input index workLimit.toNat
    valuePrefixEnd := fun index => runValueParameterPrefixAt context input index workLimit.toNat
    whenPrefixEnd := fun index => runWhenSubjectPrefixAt context input index workLimit.toNat
  }
  let result ← scanBalancedGroup input queries start.toNat
    (decodeKind opening) (decodeKind closing) (options &&& 1 != 0) (options &&& 2 != 0)
  return ((result.endIndex - start.toNat) * 4 + groupStopCode result.stop).toUInt64

end TypeArguments.FFI
