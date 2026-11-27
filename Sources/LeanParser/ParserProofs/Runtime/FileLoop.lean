import ParserProofs.Runtime.GenuineDeclarations

set_option warningAsError true

namespace TypeArguments.FFI

inductive TopLevelDispatch where
  | packageHeader | importHeader | declaration | statement | eof
  deriving DecidableEq

def encodeTopLevelDispatch : TopLevelDispatch → UInt8
  | .packageHeader => 0
  | .importHeader => 1
  | .declaration => 2
  | .statement => 3
  | .eof => 4

def directTopLevelDispatch : Kind → TopLevelDispatch
  | .packageKeyword => .packageHeader
  | .importKeyword => .importHeader
  | .declaration | .funKeyword | .objectKeyword => .declaration
  | .eof => .eof
  | _ => .statement

def topLevelDispatchAfterLookahead (kind : Kind) (verdict : GenuineVerdict) : TopLevelDispatch :=
  if kind = .context then
    if verdict = .declaration then .declaration else .statement
  else if verdict = .overBudget then .statement else .declaration

def topLevelDispatch (kind : Kind) (probe : IO GenuineVerdict) : IO TopLevelDispatch := do
  if isAmbiguousDeclarationPrefix kind then
    return topLevelDispatchAfterLookahead kind (← probe)
  else
    return directTopLevelDispatch kind

theorem topLevelContextIsDeclarationIff :
    topLevelDispatchAfterLookahead .context verdict = .declaration ↔ verdict = .declaration := by
  cases verdict <;> simp [topLevelDispatchAfterLookahead]

theorem topLevelContextIsStatementIff :
    topLevelDispatchAfterLookahead .context verdict = .statement ↔ verdict ≠ .declaration := by
  cases verdict <;> simp [topLevelDispatchAfterLookahead]

theorem topLevelOtherAmbiguousIsStatementIff (notContext : kind ≠ .context) :
    topLevelDispatchAfterLookahead kind verdict = .statement ↔ verdict = .overBudget := by
  cases verdict <;> simp [topLevelDispatchAfterLookahead, notContext]

theorem topLevelDispatchUsesLookahead (ambiguous : isAmbiguousDeclarationPrefix kind = true) :
    topLevelDispatch kind probe = (do return topLevelDispatchAfterLookahead kind (← probe)) := by
  simp [topLevelDispatch, ambiguous]

theorem topLevelDispatchSkipsLookahead (unambiguous : isAmbiguousDeclarationPrefix kind = false) :
    topLevelDispatch kind probe = pure (directTopLevelDispatch kind) := by
  simp [topLevelDispatch, unambiguous]

theorem topLevelDispatchStopsAtEOF {input : Input} {index : Nat} (terminal : (input.get index).kind = .eof) :
    topLevelDispatch (input.get index).kind probe = pure .eof := by
  simp [terminal, topLevelDispatch, isAmbiguousDeclarationPrefix, directTopLevelDispatch]

theorem fileEOFLeavesCursorAndFinishesImports {input : Input} {index : Nat}
    (terminal : (input.get index).kind = .eof) (probe : IO GenuineVerdict) (parseItem : IO (Nat × Nat)) :
    (do
      let dispatch ← topLevelDispatch (input.get index).kind probe
      if dispatch = TopLevelDispatch.eof then
        return (index, countFinishedImportGroups pending [.eof])
      else parseItem) = pure (index, if pending then 1 else 0) := by
  simp [topLevelDispatchStopsAtEOF terminal, fileEOFFinishesExactlyPendingGroup] <;> rfl

theorem topLevelOverBudgetIsStatement (ambiguous : isAmbiguousDeclarationPrefix kind = true) :
    topLevelDispatch kind (pure .overBudget) = pure .statement := by
  rw [topLevelDispatchUsesLookahead ambiguous]
  by_cases context : kind = .context <;> simp [topLevelDispatchAfterLookahead, context] <;> rfl

def enumBodyStartsDeclaration (input : Input) (index : Nat) (probe : IO GenuineVerdict) : IO Bool := do
  let token := input.get index
  if token.constructorKeyword then return true
  match token.kind with
  | .at => return !enumEntryAfterAnnotations input index
  | .context => return (← probe) == .declaration
  | .modifier => return isBareDeclarationStart (input.get (index + 1)).kind
  | .declaration | .funKeyword | .objectKeyword => return true
  | _ => return false

theorem enumBodyConstructorStartsDeclaration (constructor : (input.get index).constructorKeyword = true) :
    enumBodyStartsDeclaration input index probe = pure true := by
  simp [enumBodyStartsDeclaration, constructor]

theorem enumBodyAnnotationDispatch (annotation : (input.get index).kind = .at)
    (notConstructor : (input.get index).constructorKeyword = false) :
    enumBodyStartsDeclaration input index probe = pure (!enumEntryAfterAnnotations input index) := by
  simp [enumBodyStartsDeclaration, annotation, notConstructor] <;> rfl

theorem enumBodyContextDispatch (context : (input.get index).kind = .context)
    (notConstructor : (input.get index).constructorKeyword = false) :
    enumBodyStartsDeclaration input index (pure verdict) = pure (verdict == .declaration) := by
  simp [enumBodyStartsDeclaration, context, notConstructor] <;> rfl

theorem enumBodyModifierDispatch (modifier : (input.get index).kind = .modifier)
    (notConstructor : (input.get index).constructorKeyword = false) :
    enumBodyStartsDeclaration input index probe = pure (isBareDeclarationStart (input.get (index + 1)).kind) := by
  simp [enumBodyStartsDeclaration, modifier, notConstructor] <;> rfl

@[export kswiftk_lean_genuine_declaration]
def genuineDeclarationFrom (context count start : USize) (mode : UInt8) (workLimit : UInt32) : IO UInt64 := do
  let input := callbackInput context count
  let scan := runGenuineDeclarationAt context input start.toNat workLimit.toNat
  if mode == 3 then
    return if ← enumBodyStartsDeclaration input start.toNat scan then 1 else 0
  if mode != 0 then
    let stops ← genuineDeclarationBoundary input start.toNat scan
    return if stops then 1 else 0
  return match ← scan with
  | .notDeclaration => 0
  | .declaration => 1
  | .overBudget => 2

def fileItemAfterDispatch (dispatch : TopLevelDispatch) (kind : UInt8) : FileItem :=
  match dispatch with
  | .packageHeader => .directPackage
  | .importHeader => .importHeader
  | .declaration => topLevelDeclarationItem (decodeDeclarationNodeKind kind)
  | .statement => .topLevelStatement
  | .eof => .eof

def nextFileCursor (before expected actual limit : Nat) : Option Nat :=
  if actual = expected ∧ before < actual ∧ actual ≤ limit then some actual else none

theorem fileLoopContinuesOnlyWithProgress :
    nextFileCursor before expected actual limit = some next ↔
      next = actual ∧ actual = expected ∧ before < actual ∧ actual ≤ limit := by
  by_cases valid : actual = expected ∧ before < actual ∧ actual ≤ limit
  · rw [nextFileCursor, if_pos valid, Option.some.injEq]
    exact ⟨fun same => ⟨same.symm, valid⟩, fun result => result.1.symm⟩
  · rw [nextFileCursor, if_neg valid]
    constructor
    · intro impossible
      cases impossible
    · intro result
      exact (valid result.2).elim

theorem fileLoopStopsOnStalledCursor :
    nextFileCursor cursor expected cursor limit = none := by
  simp [nextFileCursor]

structure FileLoopCallbacks where
  probe : Nat → IO GenuineVerdict
  parse : TopLevelDispatch → IO (Nat × UInt8)
  emit : UInt8 → Nat → IO Nat

def finishFileLoop (flags : UInt8) (failed : Bool := false) : UInt64 :=
  (advanceFilePlacementFlags flags .eof).toUInt64 + if failed then 256 else 0

inductive FileLoopStep (cursor limit : Nat) where
  | done (result : UInt64)
  | advance (next : Nat) (flags : UInt8) (progress : cursor < next) (bounded : next ≤ limit)

@[noinline]
def fileLoopStep (input : Input) (callbacks : FileLoopCallbacks) (cursor : Nat) (flags : UInt8) :
    IO (FileLoopStep cursor input.count) := do
  let dispatch ← topLevelDispatch (input.get cursor).kind (callbacks.probe cursor)
  if dispatch = .eof then return .done (finishFileLoop flags)
  let (afterItem, kind) ← callbacks.parse dispatch
  if afterItem < cursor || input.count < afterItem then return .done (finishFileLoop flags true)
  let item := fileItemAfterDispatch dispatch kind
  let action := advanceFilePlacementFlags flags item
  let expected := fileSeparatorEnd input item afterItem
  let afterSeparators ← callbacks.emit action (expected - afterItem)
  let nextFlags := action &&& 15
  return match valid : nextFileCursor cursor expected afterSeparators input.count with
  | none => .done (finishFileLoop nextFlags true)
  | some next =>
    let ⟨same, _, progress, bounded⟩ := fileLoopContinuesOnlyWithProgress.mp valid
    .advance next nextFlags (same.symm ▸ progress) (same.symm ▸ bounded)

def runFileLoop (input : Input) (callbacks : FileLoopCallbacks) (cursor : Nat) (flags : UInt8) : Nat → IO UInt64
  | 0 => pure (finishFileLoop flags true)
  | remaining + 1 => do
    match ← fileLoopStep input callbacks cursor flags with
    | .done result => return result
    | .advance next nextFlags _ _ => runFileLoop input callbacks next nextFlags remaining

theorem fileLoopAtEOFDoesNotCallParseOrEmit {input : Input} {cursor : Nat}
    (terminal : (input.get cursor).kind = .eof) :
    runFileLoop input callbacks cursor flags (remaining + 1) = pure (finishFileLoop flags) := by
  simp [runFileLoop, fileLoopStep, topLevelDispatchStopsAtEOF terminal] <;> rfl

@[export kswiftk_lean_parse_file]
def parseFileFrom (context count start : USize) (work : UInt32) : IO UInt64 := do
  let input := callbackInput context count
  let callbacks : FileLoopCallbacks := {
    probe := fun index => runGenuineDeclarationAt context input index work.toNat
    parse := fun dispatch => do
      let result ← parseFileItem context (encodeTopLevelDispatch dispatch)
      return (result.toNat / 256, result.toUInt8)
    emit := fun action separators =>
      return (← emitFileItem context action separators.toUSize).toNat
  }
  runFileLoop input callbacks start.toNat 0 (count.toNat - start.toNat + 1)

end TypeArguments.FFI
