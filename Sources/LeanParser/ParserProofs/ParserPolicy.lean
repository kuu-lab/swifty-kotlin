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

@[export kswiftk_lean_classify_parser_policy]
def classify (operation first second : UInt8) : UInt8 :=
  let result := match operation with
    | 0 => startsLabel (first != 0) (decodeKind second)
    | 1 => startsLoop (decodeKind first)
    | _ => false
  if result then 1 else 0

end ParserProofs.ParserPolicy
