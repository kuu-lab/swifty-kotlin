import ParserProofs.Runtime.StatementBoundaries

set_option warningAsError true

namespace TypeArguments.FFI

inductive FileItem where
  | directPackage | prefixedPackage | importHeader | body | eof | topLevelStatement
  deriving DecidableEq

inductive DeclarationNodeKind where
  | packageHeader | importHeader | other
  deriving DecidableEq

def decodeDeclarationNodeKind : UInt8 → DeclarationNodeKind
  | 2 => .packageHeader
  | 4 => .importHeader
  | _ => .other

def topLevelDeclarationItem : DeclarationNodeKind → FileItem
  | .packageHeader => .prefixedPackage
  | .importHeader => .importHeader
  | .other => .body

theorem topLevelDeclarationIsPrefixedPackageIff :
    topLevelDeclarationItem kind = .prefixedPackage ↔ kind = .packageHeader := by
  cases kind <;> simp [topLevelDeclarationItem]

theorem topLevelDeclarationIsImportIff :
    topLevelDeclarationItem kind = .importHeader ↔ kind = .importHeader := by
  cases kind <;> simp [topLevelDeclarationItem]

theorem topLevelDeclarationIsBodyIff :
    topLevelDeclarationItem kind = .body ↔ kind ≠ .packageHeader ∧ kind ≠ .importHeader := by
  cases kind <;> simp [topLevelDeclarationItem]

structure FilePlacement where
  sawPackage : Bool
  sawBody : Bool
  sawTopLevelStatement : Bool

def advanceFilePlacement (state : FilePlacement) : FileItem → FilePlacement × Bool
  | .directPackage => ({ state with sawPackage := true }, false)
  | .prefixedPackage => (state, false)
  | .importHeader => (state, state.sawBody)
  | .body => ({ state with sawBody := true }, false)
  | .eof => (state, false)
  | .topLevelStatement => ({ state with sawBody := true, sawTopLevelStatement := true }, false)

theorem duplicatePackageKeepsFilePlacement (seen : state.sawPackage = true) :
    advanceFilePlacement state .directPackage = (state, false) := by
  cases state with
  | mk sawPackage sawBody sawTopLevelStatement =>
    change sawPackage = true at seen
    subst sawPackage
    rfl

theorem prefixedPackageKeepsFilePlacement :
    advanceFilePlacement state .prefixedPackage = (state, false) := rfl

theorem lateImportIff :
    (advanceFilePlacement state item).2 = true ↔ item = .importHeader ∧ state.sawBody = true := by
  cases item <;> simp [advanceFilePlacement]

theorem importKeepsFilePlacement :
    (advanceFilePlacement state .importHeader).1 = state := rfl

theorem fileBodyRemainsSeen (seen : state.sawBody = true) :
    (advanceFilePlacement state item).1.sawBody = true := by
  cases item <;> simp [advanceFilePlacement, seen]

def isScriptFile (state : FilePlacement) : Bool :=
  state.sawTopLevelStatement && !state.sawPackage

theorem isScriptFileIff :
    isScriptFile state = true ↔ state.sawTopLevelStatement = true ∧ state.sawPackage = false := by
  simp [isScriptFile]

theorem filePlacementSawStatementIff :
    (advanceFilePlacement state item).1.sawTopLevelStatement = true ↔
      state.sawTopLevelStatement = true ∨ item = .topLevelStatement := by
  cases item <;> simp [advanceFilePlacement]

theorem filePlacementSawPackageIff :
    (advanceFilePlacement state item).1.sawPackage = true ↔
      state.sawPackage = true ∨ item = .directPackage := by
  cases item <;> simp [advanceFilePlacement]

def filePlacementAfter (state : FilePlacement) (items : List FileItem) : FilePlacement :=
  items.foldl (fun placement item => (advanceFilePlacement placement item).1) state

theorem filePlacementAfterRecordsStatementsAndPackages (state : FilePlacement) (items : List FileItem) :
    let final := filePlacementAfter state items
    (final.sawTopLevelStatement = true ↔ state.sawTopLevelStatement = true ∨ .topLevelStatement ∈ items) ∧
      (final.sawPackage = true ↔ state.sawPackage = true ∨ .directPackage ∈ items) := by
  induction items generalizing state with
  | nil => simp [filePlacementAfter]
  | cons item rest ih =>
    simp only [filePlacementAfter, List.foldl_cons, List.mem_cons] at ih ⊢
    obtain ⟨statement, package⟩ := ih (advanceFilePlacement state item).1
    rw [statement, package, filePlacementSawStatementIff, filePlacementSawPackageIff]
    have statementEq : (item = FileItem.topLevelStatement) ↔ (FileItem.topLevelStatement = item) := eq_comm
    have packageEq : (item = FileItem.directPackage) ↔ (FileItem.directPackage = item) := eq_comm
    rw [statementEq, packageEq]
    simp [or_assoc]

theorem isScriptAfterFileItemsIff (items : List FileItem) :
    isScriptFile (filePlacementAfter ⟨false, false, false⟩ items) = true ↔
      FileItem.topLevelStatement ∈ items ∧ FileItem.directPackage ∉ items := by
  obtain ⟨statement, package⟩ := filePlacementAfterRecordsStatementsAndPackages ⟨false, false, false⟩ items
  rw [isScriptFileIff, statement]
  cases seen : (filePlacementAfter ⟨false, false, false⟩ items).sawPackage <;>
    simp_all

def fileSeparatorEnd (input : Input) (item : FileItem) (start : Nat) : Nat :=
  if item = .importHeader ∨ item = .eof then start
  else scanToStop (fun index => (input.get index).kind != .semicolon) start (input.count - start)

theorem fileSeparatorsSkipImport :
    fileSeparatorEnd input .importHeader start = start := by
  simp [fileSeparatorEnd]

theorem fileSeparatorsSkipEOFItem :
    fileSeparatorEnd input .eof start = start := by
  simp [fileSeparatorEnd]

theorem fileSeparatorsStopAtFirstNonSemicolon
    (itemAllowsSeparators : ¬(item = .importHeader ∨ item = .eof))
    (lower : start ≤ point) (upper : point ≤ input.count)
    (stop : (input.get point).kind ≠ .semicolon)
    (first : ∀ index, start ≤ index → index < point → (input.get index).kind = .semicolon) :
    fileSeparatorEnd input item start = point := by
  rw [fileSeparatorEnd, if_neg itemAllowsSeparators]
  apply scanToStopStopsAtFirst lower (by omega)
  · simp [stop]
  · intro index beginAt beforeStop
    simp [first index beginAt beforeStop]

theorem fileSeparatorsDoNotCrossNonSemicolon
    (lower : start ≤ point) (stop : (input.get point).kind ≠ .semicolon) :
    fileSeparatorEnd input item start ≤ point := by
  unfold fileSeparatorEnd
  split
  · exact lower
  · obtain ⟨_, _, skipped, _⟩ :=
      scanToStopSpec (fun index => (input.get index).kind != .semicolon) start (input.count - start)
    apply Nat.le_of_not_gt
    intro past
    simpa [stop] using skipped point lower past

theorem fileSeparatorsDoNotConsumeEOF
    (lower : start ≤ eof) (terminal : (input.get eof).kind = .eof) :
    fileSeparatorEnd input item start ≤ eof :=
  fileSeparatorsDoNotCrossNonSemicolon lower (by simp [terminal])

def advanceFileEvent (state : FilePlacement) : Option FileItem → FilePlacement
  | some item => (advanceFilePlacement state item).1
  | none => state

theorem fileSeparatorsPreservePlacement (state : FilePlacement) (input : Input) (item : FileItem) (start : Nat) :
    (List.replicate (fileSeparatorEnd input item start - start) (none : Option FileItem)).foldl
      advanceFileEvent state = state := by
  generalize fileSeparatorEnd input item start - start = count
  induction count with
  | zero => rfl
  | succ count ih => simpa [List.replicate_succ, advanceFileEvent] using ih

theorem fileSeparatorsPreserveScriptKind (state : FilePlacement) (input : Input) (item : FileItem) (start : Nat) :
    isScriptFile ((List.replicate (fileSeparatorEnd input item start - start) (none : Option FileItem)).foldl
      advanceFileEvent state) = isScriptFile state := by
  rw [fileSeparatorsPreservePlacement]

structure ImportGroupStep where
  pending : Bool
  appendImport : Bool
  flush : Bool

def advanceImportGroup (pending : Bool) : FileItem → ImportGroupStep
  | .importHeader => ⟨true, true, false⟩
  | _ => ⟨false, false, pending⟩

theorem importGroupAppendsIff :
    (advanceImportGroup pending item).appendImport = true ↔ item = .importHeader := by
  cases item <;> simp [advanceImportGroup]

theorem importGroupFlushesIff :
    (advanceImportGroup pending item).flush = true ↔ pending = true ∧ item ≠ .importHeader := by
  cases item <;> simp [advanceImportGroup]

def countFinishedImportGroups (pending : Bool) : List FileItem → Nat
  | [] => 0
  | item :: rest =>
    let step := advanceImportGroup pending item
    (if step.flush then 1 else 0) + countFinishedImportGroups step.pending rest

theorem importRunFinishesOneGroup (boundary : item ≠ .importHeader) (length : Nat) :
    countFinishedImportGroups pending (List.replicate (length + 1) FileItem.importHeader ++ [item]) = 1 := by
  induction length generalizing pending with
  | zero =>
    cases item <;> simp_all [countFinishedImportGroups, advanceImportGroup]
  | succ length ih =>
    simpa only [List.replicate_succ, List.cons_append, countFinishedImportGroups, advanceImportGroup,
      Bool.false_eq_true, if_false, Nat.zero_add] using ih (pending := true)

theorem fileEOFClosesPendingImportGroup (pending : Bool) :
    advanceImportGroup pending .eof = ⟨false, false, pending⟩ := rfl

theorem fileEOFFinishesExactlyPendingGroup (pending : Bool) :
    countFinishedImportGroups pending [.eof] = (if pending then 1 else 0) := by
  simp [countFinishedImportGroups, fileEOFClosesPendingImportGroup]

def advanceFilePlacementFlags (flags : UInt8) (node : FileItem) : UInt8 :=
  let state : FilePlacement := ⟨flags &&& 1 != 0, flags &&& 2 != 0, flags &&& 8 != 0⟩
  let (next, lateImport) := advanceFilePlacement state node
  let group := advanceImportGroup (flags &&& 4 != 0) node
  (if next.sawPackage then 1 else 0) ||| (if next.sawBody then 2 else 0) |||
    (if group.pending then 4 else 0) ||| (if next.sawTopLevelStatement then 8 else 0) |||
    (if lateImport then 16 else 0) ||| (if group.appendImport then 32 else 0) |||
    (if group.flush then 64 else 0) ||| (if node == .eof && isScriptFile next then 128 else 0)

def recoverFromNestingLimit (input : Input) (inBlock : Bool) (index : Nat) : Nat :=
  let stop := scanToSynchronizationPoint input inBlock index (input.count - index)
  if stop = index ∧ index < input.count ∧ (input.get index).kind ≠ .eof then index + 1
  else stop

theorem recoverFromNestingLimitLeavesFirstLaterPoint
    (later : index < point) (upper : point ≤ input.count)
    (hit : synchronizationPointAt input inBlock point = true)
    (first : ∀ visited, index ≤ visited → visited < point →
      synchronizationPointAt input inBlock visited = false) :
    recoverFromNestingLimit input inBlock index = point := by
  have scan := scanToSynchronizationPointStopsAtFirst (Nat.le_of_lt later)
    (by omega : point ≤ index + (input.count - index)) hit first
  simp [recoverFromNestingLimit, scan, Nat.ne_of_gt later]

theorem recoverFromNestingLimitConsumesInitialPoint
    (available : index < input.count)
    (hit : synchronizationPointAt input inBlock index = true)
    (notEOF : (input.get index).kind ≠ .eof) :
    recoverFromNestingLimit input inBlock index = index + 1 := by
  have scan := scanToSynchronizationPointStopsAtFirst (Nat.le_refl index)
    (by omega : index ≤ index + (input.count - index)) hit (by omega)
  simp [recoverFromNestingLimit, scan, available, notEOF]

theorem recoverFromNestingLimitDoesNotConsumeEOF
    (lower : index ≤ eof) (terminal : (input.get eof).kind = .eof) :
    recoverFromNestingLimit input inBlock index ≤ eof := by
  dsimp only [recoverFromNestingLimit]
  split
  · next exception =>
    have different : index ≠ eof := by
      intro atEOF
      simp [atEOF, terminal] at exception
    omega
  · exact scanToSynchronizationPointDoesNotConsumeEOF lower terminal

def continuesAfterBlockAcrossNewline (sawTry : Bool) : Kind → Bool
  | .catchKeyword | .finallyKeyword => sawTry
  | .plus | .minus => false
  | kind => continuesExpressionAfterNewline kind

def continuesAfterBlock (input : Input) (index : Nat) (sawTry : Bool) : Bool :=
  let token := input.get index
  continuesAfterBlockAcrossNewline sawTry token.kind ||
    (!token.newline &&
      (token.kind == .plus || token.kind == .minus || token.kind == .openParen ||
        isTrailingLambdaOperatorContinuation input index))

theorem continuesAfterBlockAcrossNewlineIff :
    continuesAfterBlockAcrossNewline sawTry kind = true ↔
      (sawTry = true ∧ (kind = .catchKeyword ∨ kind = .finallyKeyword)) ∨
      (continuesExpressionAfterNewline kind = true ∧ kind ≠ .plus ∧ kind ≠ .minus) := by
  cases kind <;> simp [continuesAfterBlockAcrossNewline, continuesExpressionAfterNewline]

theorem continuesAfterBlockWithNewlineIff
    (newline : (input.get index).newline = true) :
    continuesAfterBlock input index sawTry = true ↔
      continuesAfterBlockAcrossNewline sawTry (input.get index).kind = true := by
  simp [continuesAfterBlock, newline]

theorem continuesAfterBlockOnSameLineIff
    (newline : (input.get index).newline = false) :
    continuesAfterBlock input index sawTry = true ↔
      continuesAfterBlockAcrossNewline sawTry (input.get index).kind = true ∨
        (input.get index).kind = .plus ∨ (input.get index).kind = .minus ∨
        (input.get index).kind = .openParen ∨
        isTrailingLambdaOperatorContinuation input index = true := by
  simp [continuesAfterBlock, newline, or_assoc]

theorem stopsAfterBlockIff :
    continuesAfterBlock input index sawTry = false ↔
      continuesAfterBlockAcrossNewline sawTry (input.get index).kind = false ∧
        ((input.get index).newline = true ∨
          ((input.get index).kind ≠ .plus ∧ (input.get index).kind ≠ .minus ∧
            (input.get index).kind ≠ .openParen ∧
            isTrailingLambdaOperatorContinuation input index = false)) := by
  cases newline : (input.get index).newline <;>
    simp [continuesAfterBlock, newline, and_assoc]

theorem stopsAfterBlockAtEOF (eof : (input.get index).kind = .eof) :
    continuesAfterBlock input index sawTry = false := by
  simp [continuesAfterBlock, continuesAfterBlockAcrossNewline, continuesExpressionAfterNewline,
    isTrailingLambdaOperatorContinuation, eof]

end TypeArguments.FFI
