import ParserProofs.TypeArgumentConsumption

set_option warningAsError true

namespace ParserProofs.ParserPolicy
open TypeArgumentStart

def startsLabel (identifierLike : Bool) (next : Kind) : Bool :=
  identifierLike && next == .at

theorem startsLabelIff :
    startsLabel identifierLike next = true ↔ identifierLike = true ∧ next = .at := by
  simp [startsLabel]

def startsLoop : Kind → Bool
  | .forKeyword | .whileKeyword | .doKeyword => true
  | _ => false

theorem startsLoopIff :
    startsLoop kind = true ↔ kind = .forKeyword ∨ kind = .whileKeyword ∨ kind = .doKeyword := by
  cases kind <;> simp [startsLoop]

def startsTypeNameAfter : Kind → Bool
  | .colon | .dot | .questionDot | .openAngle | .comma | .openParen | .arrow | .varianceIn | .varianceOut => true
  | _ => false

theorem startsTypeNameAfterIff :
    startsTypeNameAfter kind = true ↔
      kind ∈ ([.colon, .dot, .questionDot, .openAngle, .comma, .openParen, .arrow,
        .varianceIn, .varianceOut] : List Kind) := by
  cases kind <;> simp [startsTypeNameAfter]

def whenConditionContinues (next : Kind) : Kind → Bool
  | .dot | .questionDot | .bangBang | .questionColon | .ampAmp | .barBar
  | .isKeyword | .varianceIn | .asKeyword => true
  | .bang => next == .isKeyword || next == .varianceIn
  | _ => false

theorem whenConditionContinuesIff :
    whenConditionContinues next kind = true ↔
      kind ∈ ([.dot, .questionDot, .bangBang, .questionColon, .ampAmp, .barBar,
        .isKeyword, .varianceIn, .asKeyword] : List Kind) ∨
      (kind = .bang ∧ (next = .isKeyword ∨ next = .varianceIn)) := by
  cases kind <;> simp [whenConditionContinues]

def startsObjectExpression (first next : Kind) : Bool :=
  first == .objectKeyword && (next == .colon || next == .openBrace)

theorem startsObjectExpressionIff :
    startsObjectExpression first next = true ↔
      first = .objectKeyword ∧ (next = .colon ∨ next = .openBrace) := by
  simp [startsObjectExpression]

def startsBackingField (first next : Kind) : Bool :=
  first == .fieldKeyword && (next == .assign || next == .colon)

theorem startsBackingFieldIff :
    startsBackingField first next = true ↔
      first = .fieldKeyword ∧ (next = .assign ∨ next = .colon) := by
  simp [startsBackingField]

def ambiguousDeclarationPrefix : Kind → Bool
  | .at | .context | .modifier => true
  | _ => false

theorem ambiguousDeclarationPrefixIff :
    ambiguousDeclarationPrefix kind = true ↔ kind = .at ∨ kind = .context ∨ kind = .modifier := by
  cases kind <;> simp [ambiguousDeclarationPrefix]

def isHardCompanionName : Kind → Bool
  | .identifier | .modifier | .catchKeyword | .companionKeyword | .constructorKeyword
  | .dynamicKeyword | .enumKeyword | .finallyKeyword | .importKeyword | .reifiedKeyword => true
  | _ => false

def isCompanionName (kind : Kind) (soft : Bool) : Bool :=
  if soft then kind != .softWhenKeyword else isHardCompanionName kind

theorem isCompanionNameIff :
    isCompanionName kind soft = true ↔
      (soft = true ∧ kind ≠ .softWhenKeyword) ∨
      (soft = false ∧ kind ∈ ([.identifier, .modifier, .catchKeyword, .companionKeyword, .constructorKeyword,
        .dynamicKeyword, .enumKeyword, .finallyKeyword, .importKeyword, .reifiedKeyword] : List Kind)) := by
  cases soft <;> cases kind <;> simp [isCompanionName, isHardCompanionName]

def startsDeclaration : Kind → Bool
  | .at | .context | .modifier | .declarationKeyword | .objectKeyword | .enumKeyword | .companionKeyword => true
  | _ => false

theorem startsDeclarationIff :
    startsDeclaration kind = true ↔
      kind ∈ ([.at, .context, .modifier, .declarationKeyword, .objectKeyword, .enumKeyword, .companionKeyword] :
        List Kind) := by
  cases kind <;> simp [startsDeclaration]

def continuesHeader (includeBlock classColon delegation : Bool) (kind : Kind) : Bool :=
  (includeBlock && (kind == .colon || kind == .openAngle || kind == .whereKeyword)) ||
    (classColon && kind == .openParen) || (delegation && kind == .byKeyword)

def stopsDeclarationHeaderAtNewline (newline includeBlock classColon delegation : Bool) (kind : Kind) : Bool :=
  newline && (if includeBlock then !continuesHeader includeBlock classColon delegation kind else startsDeclaration kind)

theorem continuesHeaderIff :
    continuesHeader includeBlock classColon delegation kind = true ↔
      (includeBlock = true ∧ (kind = .colon ∨ kind = .openAngle ∨ kind = .whereKeyword)) ∨
      (classColon = true ∧ kind = .openParen) ∨ (delegation = true ∧ kind = .byKeyword) := by
  simp [continuesHeader, or_assoc]

theorem stopsDeclarationHeaderAtNewlineIff :
    stopsDeclarationHeaderAtNewline newline includeBlock classColon delegation kind = true ↔
      newline = true ∧
        ((includeBlock = true ∧ continuesHeader true classColon delegation kind = false) ∨
         (includeBlock = false ∧ startsDeclaration kind = true)) := by
  cases includeBlock <;> simp [stopsDeclarationHeaderAtNewline]

@[export kswiftk_lean_classify_parser_policy]
def classify (operation first second : UInt8) : UInt8 :=
  let result := match operation with
    | 0 => startsLabel (first != 0) (decodeKind second)
    | 1 => startsLoop (decodeKind first)
    | 2 => startsTypeNameAfter (decodeKind first)
    | 3 => whenConditionContinues (decodeKind second) (decodeKind first)
    | 4 => startsObjectExpression (decodeKind first) (decodeKind second)
    | 5 => startsBackingField (decodeKind first) (decodeKind second)
    | 6 => ambiguousDeclarationPrefix (decodeKind first)
    | 7 => isCompanionName (decodeKind first) (second != 0)
    | 8 => startsDeclaration (decodeKind first)
    | 9 => stopsDeclarationHeaderAtNewline (second &&& 8 != 0) (second &&& 1 != 0)
        (second &&& 2 != 0) (second &&& 4 != 0) (decodeKind first)
    | _ => false
  if result then 1 else 0

end ParserProofs.ParserPolicy
