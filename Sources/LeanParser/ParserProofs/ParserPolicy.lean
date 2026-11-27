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

@[export kswiftk_lean_classify_parser_policy]
def classify (operation first second : UInt8) : UInt8 :=
  let result := match operation with
    | 0 => startsLabel (first != 0) (decodeKind second)
    | 1 => startsLoop (decodeKind first)
    | 2 => startsTypeNameAfter (decodeKind first)
    | 3 => whenConditionContinues (decodeKind second) (decodeKind first)
    | 4 => startsObjectExpression (decodeKind first) (decodeKind second)
    | 5 => startsBackingField (decodeKind first) (decodeKind second)
    | _ => false
  if result then 1 else 0

end ParserProofs.ParserPolicy
