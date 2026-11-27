import ParserProofs.Runtime.FileHeaders

set_option warningAsError true

namespace TypeArguments.FFI

inductive DeclarationDispatch where
  | classDecl | objectDecl | interfaceDecl | funInterface | function | property | typeAlias
  | enumDecl | packageHeader | importHeader | constructor
  | companionObject | companionBlock | retryAfterCompanion | retryAfterEnum
  | statement | prefixedStatement | invalidAccessor
  deriving DecidableEq

def declarationRecoveryDispatch (head : Kind) (hasPrefix : Bool) : DeclarationDispatch :=
  if !hasPrefix then .statement
  else if head == .accessorKeyword then .invalidAccessor
  else .prefixedStatement

def declarationDispatch (head : Kind) (next : LexToken) (hasPrefix : Bool) : DeclarationDispatch :=
  match head with
  | .classKeyword => .classDecl
  | .objectKeyword => .objectDecl
  | .interfaceKeyword => .interfaceDecl
  | .funKeyword => if next.kind == .interfaceKeyword then .funInterface else .function
  | .propertyKeyword => .property
  | .typeAliasKeyword => .typeAlias
  | .enumKeyword => if next.kind == .classKeyword || next.identifierLike then .enumDecl else .retryAfterEnum
  | .packageKeyword => .packageHeader
  | .importKeyword => .importHeader
  | .constructorKeyword => .constructor
  | .companionKeyword =>
    match next.kind with
    | .objectKeyword => .companionObject
    | .openBrace => .companionBlock
    | _ => .retryAfterCompanion
  | _ => declarationRecoveryDispatch head hasPrefix

def DeclarationDispatch.isRecovery : DeclarationDispatch → Bool
  | .statement | .prefixedStatement | .invalidAccessor => true
  | _ => false

theorem declarationDispatchFixedHeads :
    declarationDispatch .classKeyword next hasPrefix = .classDecl ∧
    declarationDispatch .objectKeyword next hasPrefix = .objectDecl ∧
    declarationDispatch .interfaceKeyword next hasPrefix = .interfaceDecl ∧
    declarationDispatch .propertyKeyword next hasPrefix = .property ∧
    declarationDispatch .typeAliasKeyword next hasPrefix = .typeAlias ∧
    declarationDispatch .packageKeyword next hasPrefix = .packageHeader ∧
    declarationDispatch .importKeyword next hasPrefix = .importHeader ∧
    declarationDispatch .constructorKeyword next hasPrefix = .constructor := by
  simp [declarationDispatch]

theorem declarationDispatchFunInterfaceIff :
    declarationDispatch .funKeyword next hasPrefix = .funInterface ↔ next.kind = .interfaceKeyword := by
  by_cases kind : next.kind = .interfaceKeyword <;> simp [declarationDispatch, kind]

theorem declarationDispatchFunctionIff :
    declarationDispatch .funKeyword next hasPrefix = .function ↔ next.kind ≠ .interfaceKeyword := by
  by_cases kind : next.kind = .interfaceKeyword <;> simp [declarationDispatch, kind]

theorem declarationDispatchEnumIff :
    declarationDispatch .enumKeyword next hasPrefix = .enumDecl ↔
      next.kind = .classKeyword ∨ next.identifierLike = true := by
  by_cases kind : next.kind = .classKeyword <;> cases ident : next.identifierLike <;>
    simp [declarationDispatch, kind, ident]

theorem declarationDispatchRetryEnumIff :
    declarationDispatch .enumKeyword next hasPrefix = .retryAfterEnum ↔
      next.kind ≠ .classKeyword ∧ next.identifierLike = false := by
  by_cases kind : next.kind = .classKeyword <;> cases ident : next.identifierLike <;>
    simp [declarationDispatch, kind, ident]

theorem declarationDispatchCompanion :
    (declarationDispatch .companionKeyword next hasPrefix = .companionObject ↔ next.kind = .objectKeyword) ∧
    (declarationDispatch .companionKeyword next hasPrefix = .companionBlock ↔ next.kind = .openBrace) ∧
    (declarationDispatch .companionKeyword next hasPrefix = .retryAfterCompanion ↔
      next.kind ≠ .objectKeyword ∧ next.kind ≠ .openBrace) := by
  cases kind : next.kind <;> simp [declarationDispatch, kind]

theorem declarationDispatchRecoveryIff :
    (declarationDispatch head next hasPrefix).isRecovery = true ↔
      head ∉ ([.classKeyword, .objectKeyword, .interfaceKeyword, .funKeyword, .propertyKeyword, .typeAliasKeyword,
        .enumKeyword, .packageKeyword, .importKeyword, .constructorKeyword, .companionKeyword] : List Kind) := by
  cases head <;>
    simp [declarationDispatch, declarationRecoveryDispatch, DeclarationDispatch.isRecovery] <;>
    try (cases hasPrefix <;> rfl)
  case funKeyword =>
    by_cases interface : next.kind = .interfaceKeyword <;> simp [interface]
  case enumKeyword =>
    by_cases accepts : next.kind = .classKeyword ∨ next.identifierLike = true <;> simp [accepts]
  case companionKeyword =>
    cases next.kind <;> rfl

theorem declarationDispatchRetryRequiresNonEOF
    (retry : declarationDispatch head next hasPrefix = .retryAfterCompanion ∨
      declarationDispatch head next hasPrefix = .retryAfterEnum) :
    head ≠ .eof := by
  intro eof
  cases hasPrefix <;> simp [eof, declarationDispatch, declarationRecoveryDispatch] at retry

theorem declarationDispatchRecoveryBehavior
    (recovering : (declarationDispatch head next hasPrefix).isRecovery = true) :
    (declarationDispatch head next hasPrefix = .statement ↔ hasPrefix = false) ∧
    (declarationDispatch head next hasPrefix = .invalidAccessor ↔ hasPrefix = true ∧ head = .accessorKeyword) ∧
    (declarationDispatch head next hasPrefix = .prefixedStatement ↔ hasPrefix = true ∧ head ≠ .accessorKeyword) := by
  have fallback : declarationDispatch head next hasPrefix = declarationRecoveryDispatch head hasPrefix := by
    have other := declarationDispatchRecoveryIff.mp recovering
    cases head <;> simp_all [declarationDispatch]
  rw [fallback]
  cases hasPrefix <;> by_cases accessor : head = .accessorKeyword <;>
    simp [declarationRecoveryDispatch, accessor]

theorem declarationDispatchEOF (next : LexToken) :
    declarationDispatch .eof next false = .statement ∧
    declarationDispatch .eof next true = .prefixedStatement := by
  simp [declarationDispatch, declarationRecoveryDispatch]

def encodeDeclarationDispatch : DeclarationDispatch → Nat
  | .classDecl => 0 | .objectDecl => 1 | .interfaceDecl => 2 | .funInterface => 3
  | .function => 4 | .property => 5 | .typeAlias => 6 | .enumDecl => 7 | .packageHeader => 8
  | .importHeader => 9 | .constructor => 10 | .companionObject => 11 | .companionBlock => 12
  | .retryAfterCompanion => 13 | .retryAfterEnum => 14 | .statement => 15
  | .prefixedStatement => 16 | .invalidAccessor => 17

inductive DeclarationContextClause where
  | absent
  | group
  | missingOpen
  deriving DecidableEq

def declarationContextClauseAt (input : Input) (index : Nat) : DeclarationContextClause :=
  if (input.get index).kind != .context then .absent
  else if (input.get (index + 1)).kind == .openParen then .group
  else .missingOpen

theorem declarationContextClauseAbsentIff :
    declarationContextClauseAt input index = .absent ↔ (input.get index).kind ≠ .context := by
  by_cases context : (input.get index).kind = .context <;>
    by_cases opening : (input.get (index + 1)).kind = .openParen <;>
    simp [declarationContextClauseAt, context, opening]

theorem declarationContextClauseGroupIff :
    declarationContextClauseAt input index = .group ↔
      (input.get index).kind = .context ∧ (input.get (index + 1)).kind = .openParen := by
  by_cases context : (input.get index).kind = .context <;>
    by_cases opening : (input.get (index + 1)).kind = .openParen <;>
    simp [declarationContextClauseAt, context, opening]

theorem declarationContextClauseMissingOpenIff :
    declarationContextClauseAt input index = .missingOpen ↔
      (input.get index).kind = .context ∧ (input.get (index + 1)).kind ≠ .openParen := by
  by_cases context : (input.get index).kind = .context <;>
    by_cases opening : (input.get (index + 1)).kind = .openParen <;>
    simp [declarationContextClauseAt, context, opening]

inductive DeclarationPrefixHead where
  | contextFirst (clause : DeclarationContextClause)
  | prefixFirst (scanned : GroupResult) (clause : DeclarationContextClause)

def planDeclarationPrefixHead (input : Input) (start : Nat) : DeclarationPrefixHead :=
  match declarationContextClauseAt input start with
  | .absent =>
    let scanned := scanLeadingPrefix input .declaration start (input.count - start + 1)
    .prefixFirst scanned (declarationContextClauseAt input scanned.endIndex)
  | clause => .contextFirst clause

theorem declarationPrefixHeadContextFirstIff :
    planDeclarationPrefixHead input start = .contextFirst clause ↔
      declarationContextClauseAt input start = clause ∧ clause ≠ .absent := by
  cases found : declarationContextClauseAt input start <;>
    cases clause <;> simp [planDeclarationPrefixHead, found]

theorem declarationPrefixHeadScansBeforeSecondContext
    (nonContext : (input.get start).kind ≠ .context) :
    let scanned := scanLeadingPrefix input .declaration start (input.count - start + 1)
    planDeclarationPrefixHead input start = .prefixFirst scanned
      (declarationContextClauseAt input scanned.endIndex) := by
  simp [planDeclarationPrefixHead, declarationContextClauseAbsentIff.mpr nonContext]

theorem declarationPrefixHeadAtEOF (eof : (input.get start).kind = .eof) :
    planDeclarationPrefixHead input start = .prefixFirst ⟨.eof, start⟩ .absent := by
  simp [planDeclarationPrefixHead, declarationContextClauseAt, scanLeadingPrefix, leadingPrefixStep,
    isLeadingPrefix, eof]

def encodeDeclarationContextClause : DeclarationContextClause → Nat
  | .absent => 0
  | .group => 1
  | .missingOpen => 2

def encodeDeclarationPrefixHead (start : Nat) : DeclarationPrefixHead → Nat
  | .contextFirst clause => 16 + encodeDeclarationContextClause clause * 4
  | .prefixFirst scanned clause =>
    (scanned.endIndex - start) * 32 + encodeDeclarationContextClause clause * 4 + groupStopCode scanned.stop

def labelStartsAt (input : Input) (index : Nat) : Bool :=
  (input.get index).identifierLike && (input.get (index + 1)).kind == .at

theorem labelStartsAtIff :
    labelStartsAt input index = true ↔
      (input.get index).identifierLike = true ∧ (input.get (index + 1)).kind = .at := by
  simp [labelStartsAt]

def startsLoop (kind : Kind) : Bool := kind == .loopKeyword

theorem startsLoopIff : startsLoop kind = true ↔ kind = .loopKeyword := by simp [startsLoop]

def canStartTypeNameAfter : Kind → Bool
  | .colon | .dot | .questionDot | .openAngle | .comma | .openParen | .arrow | .varianceIn | .varianceOut => true
  | _ => false

theorem canStartTypeNameAfterIff :
    canStartTypeNameAfter kind = true ↔
      kind ∈ ([.colon, .dot, .questionDot, .openAngle, .comma, .openParen, .arrow,
        .varianceIn, .varianceOut] : List Kind) := by
  cases kind <;> simp [canStartTypeNameAfter]

def whenConditionContinuesAfterLineBreak (next : Kind) : Kind → Bool
  | .dot | .questionDot | .bangBang | .questionColon | .ampAmp | .barBar
  | .isKeyword | .varianceIn | .asKeyword => true
  | .bang => next == .isKeyword || next == .varianceIn
  | _ => false

theorem whenConditionContinuesAfterLineBreakIff :
    whenConditionContinuesAfterLineBreak next kind = true ↔
      kind ∈ ([.dot, .questionDot, .bangBang, .questionColon, .ampAmp, .barBar,
        .isKeyword, .varianceIn, .asKeyword] : List Kind) ∨
      (kind = .bang ∧ (next = .isKeyword ∨ next = .varianceIn)) := by
  cases kind <;> simp [whenConditionContinuesAfterLineBreak]

def isCompanionNameKind : Kind → Bool
  | .identifier | .modifier | .catchKeyword | .companionKeyword | .constructorKeyword | .enumKeyword
  | .finallyKeyword | .importKeyword | .companionNameKeyword => true
  | _ => false

def isCompanionObjectName (token : LexToken) : Bool :=
  if token.softKeyword then token.kind != .softWhenKeyword else isCompanionNameKind token.kind

theorem isCompanionObjectNameIff :
    isCompanionObjectName token = true ↔
      (token.softKeyword = true ∧ token.kind ≠ .softWhenKeyword) ∨
      (token.softKeyword = false ∧ token.kind ∈ ([.identifier, .modifier, .catchKeyword, .companionKeyword,
        .constructorKeyword, .enumKeyword, .finallyKeyword, .importKeyword, .companionNameKeyword] : List Kind)) := by
  cases soft : token.softKeyword <;> cases kind : token.kind <;> simp [isCompanionObjectName, isCompanionNameKind, soft, kind]

def isBareDeclarationStart : Kind → Bool
  | .at | .context | .modifier | .declaration | .objectKeyword | .funKeyword
  | .enumKeyword | .companionKeyword | .packageKeyword => true
  | _ => false

theorem isBareDeclarationStartIff :
    isBareDeclarationStart kind = true ↔
      kind ∈ ([.at, .context, .modifier, .declaration, .objectKeyword, .funKeyword,
        .enumKeyword, .companionKeyword, .packageKeyword] : List Kind) := by
  cases kind <;> simp [isBareDeclarationStart]

def continuesDeclarationHeader (includeBlock allowsClassHeaderColon allowsClassDelegation : Bool) (kind : Kind) : Bool :=
  (includeBlock && (kind == .colon || kind == .openAngle || kind == .whereKeyword)) ||
    (allowsClassHeaderColon && kind == .openParen) || (allowsClassDelegation && kind == .byKeyword)

def stopsDeclarationHeaderAtNewline (includeBlock allowsClassHeaderColon allowsClassDelegation : Bool)
    (token : LexToken) : Bool :=
  token.newline && (if includeBlock then !continuesDeclarationHeader includeBlock allowsClassHeaderColon
    allowsClassDelegation token.kind else isBareDeclarationStart token.kind)

theorem continuesDeclarationHeaderIff :
    continuesDeclarationHeader includeBlock allowsClassHeaderColon allowsClassDelegation kind = true ↔
      (includeBlock = true ∧ (kind = .colon ∨ kind = .openAngle ∨ kind = .whereKeyword)) ∨
      (allowsClassHeaderColon = true ∧ kind = .openParen) ∨
      (allowsClassDelegation = true ∧ kind = .byKeyword) := by
  simp [continuesDeclarationHeader, or_assoc]

theorem stopsDeclarationHeaderAtNewlineIff :
    stopsDeclarationHeaderAtNewline includeBlock allowsClassHeaderColon allowsClassDelegation token = true ↔
      token.newline = true ∧
        ((includeBlock = true ∧
          continuesDeclarationHeader true allowsClassHeaderColon allowsClassDelegation token.kind = false) ∨
         (includeBlock = false ∧ isBareDeclarationStart token.kind = true)) := by
  cases includeBlock <;> simp [stopsDeclarationHeaderAtNewline]

inductive ConstructorTailStep where
  | stop
  | consumeTerminator
  | advance (depth : Nat)
  deriving DecidableEq

def constructorTailStopsAtTop (token : LexToken) : Bool :=
  token.kind == .openBrace || token.kind == .closeBrace ||
    (token.newline && token.kind != .colon && token.kind != .constructorDelegationKeyword)

def constructorTailStep (token : LexToken) (depth : Nat) : ConstructorTailStep :=
  if token.kind = .eof ∨ (depth = 0 ∧ constructorTailStopsAtTop token = true) then .stop
  else if depth = 0 ∧ token.kind = .semicolon then .consumeTerminator
  else if token.kind = .openParen then .advance (depth + 1)
  else if token.kind = .closeParen then .advance (depth - 1)
  else .advance depth

theorem constructorTailStopsAtTopIff :
    constructorTailStopsAtTop token = true ↔
      token.kind = .openBrace ∨ token.kind = .closeBrace ∨
      (token.newline = true ∧ token.kind ≠ .colon ∧ token.kind ≠ .constructorDelegationKeyword) := by
  simp [constructorTailStopsAtTop, or_assoc, and_assoc]

theorem constructorTailStepStopsIff :
    constructorTailStep token depth = .stop ↔
      token.kind = .eof ∨ (depth = 0 ∧ constructorTailStopsAtTop token = true) := by
  by_cases stop : token.kind = .eof ∨ (depth = 0 ∧ constructorTailStopsAtTop token = true)
  · simp [constructorTailStep, stop]
  · by_cases terminator : depth = 0 ∧ token.kind = .semicolon <;>
      by_cases opening : token.kind = .openParen <;> by_cases closing : token.kind = .closeParen <;>
      simp [constructorTailStep, stop, terminator, opening, closing]

theorem constructorTailStepConsumesTerminatorIff :
    constructorTailStep token depth = .consumeTerminator ↔
      depth = 0 ∧ token.kind = .semicolon ∧ token.newline = false := by
  by_cases semi : token.kind = .semicolon
  · cases depth <;> cases newline : token.newline <;>
      simp [constructorTailStep, constructorTailStopsAtTop, semi, newline]
  · unfold constructorTailStep
    split
    · simp [semi]
    · by_cases opening : token.kind = .openParen <;> by_cases closing : token.kind = .closeParen <;>
        simp [semi, opening, closing]

def scanConstructorTail (input : Input) (index depth : Nat) : Nat → Nat
  | 0 => index
  | fuel + 1 =>
    match constructorTailStep (input.get index) depth with
    | .stop => index
    | .consumeTerminator => index + 1
    | .advance nextDepth => scanConstructorTail input (index + 1) nextDepth fuel

theorem scanConstructorTailLeavesEOF (terminal : (input.get index).kind = .eof) :
    scanConstructorTail input index depth fuel = index := by
  cases fuel <;> simp [scanConstructorTail, constructorTailStep, terminal]

theorem scanConstructorTailWithinFuel :
    index ≤ scanConstructorTail input index depth fuel ∧
      scanConstructorTail input index depth fuel ≤ index + fuel := by
  induction fuel generalizing index depth with
  | zero => simp [scanConstructorTail]
  | succ fuel ih =>
    cases step : constructorTailStep (input.get index) depth with
    | stop => simp [scanConstructorTail, step]
    | consumeTerminator => simp [scanConstructorTail, step] <;> omega
    | advance nextDepth =>
      simp only [scanConstructorTail, step]
      obtain ⟨lower, upper⟩ := ih (index := index + 1) (depth := nextDepth)
      omega

def scanWhenSubjectBackwards (input : Input) (index depth : Nat) : Nat → Bool
  | 0 => false
  | fuel + 1 =>
    let kind := (input.get index).kind
    match kind with
    | .nonToken => scanWhenSubjectBackwards input (index + 1) depth fuel
    | .closeParen => scanWhenSubjectBackwards input (index + 1) (depth + 1) fuel
    | .openParen => depth != 0 && scanWhenSubjectBackwards input (index + 1) (depth - 1) fuel
    | _ => if depth == 0 then kind == .whenKeyword
           else scanWhenSubjectBackwards input (index + 1) depth fuel

theorem scanWhenSubjectBackwardsStopsAtUnmatchedOpen (opening : (input.get index).kind = .openParen) :
    scanWhenSubjectBackwards input index 0 (fuel + 1) = false := by
  simp [scanWhenSubjectBackwards, opening]

theorem scanWhenSubjectBackwardsSkipsNonTokens (child : (input.get index).kind = .nonToken) :
    scanWhenSubjectBackwards input index depth (fuel + 1) =
      scanWhenSubjectBackwards input (index + 1) depth fuel := by
  simp [scanWhenSubjectBackwards, child]

theorem scanWhenSubjectBackwardsChecksKeyword
    (token : (input.get index).kind ∉ ([.nonToken, .closeParen, .openParen] : List Kind)) :
    scanWhenSubjectBackwards input index 0 (fuel + 1) = true ↔ (input.get index).kind = .whenKeyword := by
  generalize h : (input.get index).kind = kind at token ⊢
  cases kind <;> simp_all [scanWhenSubjectBackwards]

@[export kswiftk_lean_parser_lookahead]
def lookaheadFrom (context count start : USize) (operation : UInt8) (argument : USize) : USize :=
  let input := callbackInput context count
  let position := start.toNat
  let result := match operation with
    | 0 => some (offsetPastAngles input position)
    | 1 => some (offsetPastParens input position (if argument == 0 then none else some (argument.toNat - 1)))
    | 2 => annotationTail input (position + 1)
    | 3 => some (if defaultStartsTypeArguments input position (argument != 0) then 1 else 0)
    | 4 => some (if anonymousFunctionAt input position then 1 else 0)
    | 5 =>
      let mode : LeadingPrefixMode :=
        if argument == 1 then .annotations else if argument == 2 then .receiver else .declaration
      let scanned := scanLeadingPrefix input mode position (input.count - position + 1)
      some ((scanned.endIndex - position) * 4 + groupStopCode scanned.stop)
    | 6 => some (if enumEntryAfterAnnotations input position then 1 else 0)
    | 7 => some (if startsPrimaryConstructorHeader input position then 1 else 0)
    | 8 => some (if scanPropertyTailAccessors input position (input.count - position) then 1 else 0)
    | 9 => some (if explicitBackingFieldAt input position then 1 else 0)
    | 10 => some (if objectExpressionAt input position then 1 else 0)
    | 11 => some (if isAmbiguousDeclarationPrefix (decodeKind argument.toUInt8) then 1 else 0)
    | 12 => some (if continuesAfterBlock input position (argument != 0) then 1 else 0)
    | 13 => some (if continuesExpressionAfterNewline (decodeKind argument.toUInt8) then 1 else 0)
    | 14 => some (skipToSynchronizationPoint input (argument != 0) position)
    | 15 => some (recoverFromNestingLimit input (argument != 0) position)
    | 16 => some (qualifiedPathEnd input (argument &&& 1 != 0) (argument &&& 2 != 0) position)
    | 17 => some ((scanHeaderDeclaration input (argument != 0) position).encode position)
    | 19 =>
      match topLevelStatementRecovery input argument.toNat position with
      | none => some 0
      | some plan => some ((plan.skippedEnd - position) * 2 + (if plan.forceAdvance then 2 else 1))
    | 20 =>
      some (encodeDeclarationDispatch (declarationDispatch (input.get position).kind (input.get (position + 1))
        (argument != 0)))
    | 21 => some (encodeDeclarationPrefixHead position (planDeclarationPrefixHead input position))
    | 22 => some (if labelStartsAt input position then 1 else 0)
    | 23 => some (if startsLoop (decodeKind argument.toUInt8) then 1 else 0)
    | 24 => some (if canStartTypeNameAfter (decodeKind argument.toUInt8) then 1 else 0)
    | 25 => some (if whenConditionContinuesAfterLineBreak (input.get (position + 1)).kind
        (input.get position).kind then 1 else 0)
    | 26 => some (if isCompanionObjectName (decodeToken argument.toUInt32) then 1 else 0)
    | 27 => some (if isBareDeclarationStart (decodeKind argument.toUInt8) then 1 else 0)
    | 28 => some (scanConstructorTail input position 0 (input.count - position + 1))
    | 29 => some (if stopsDeclarationHeaderAtNewline (argument &&& 1 != 0) (argument &&& 2 != 0)
        (argument &&& 4 != 0) (input.get position) then 1 else 0)
    | 30 => some (if scanWhenSubjectBackwards input position 0 input.count then 1 else 0)
    | _ => none
  match result with
  | some index => index.toUSize + 1
  | none => 0

end TypeArguments.FFI
