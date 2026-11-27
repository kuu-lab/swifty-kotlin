import ParserProofs.TypeArgumentOffset
import ParserProofs.TypeArguments

set_option warningAsError true

namespace ParserProofs.TypeArgumentConsumption
open TypeArgumentStart

@[extern "kswiftk_lean_read_type_argument_boundary"]
opaque readBoundary (context index : USize) : IO Bool

def projectToken (boundary : IO Bool) (depth : Nat) : Kind → IO TypeArguments.Token
  | .openAngle => pure .openAngle
  | .closeAngle => pure .closeAngle
  | .eof => pure .eof
  | _ => if depth = 0 then do return if ← boundary then .boundary else .other else pure .other

theorem projectionLeavesNestedBoundaryUnprobed (nested : depth ≠ 0)
    (notOpening : kind ≠ .openAngle) (notClosing : kind ≠ .closeAngle) (notEOF : kind ≠ .eof) :
    projectToken boundary depth kind = pure .other := by
  cases kind <;> simp_all [projectToken]

theorem projectionNeverProbesEOF :
    projectToken boundary depth .eof = pure .eof := rfl

inductive ProjectionStep where
  | stop (token : TypeArguments.Token)
  | advance (token : TypeArguments.Token) (depth : Nat)

@[noinline]
def projectionStep (input : Input) (context : USize) (index depth : Nat) : IO ProjectionStep := do
  let token ← projectToken (readBoundary context index.toUSize) depth (input.get index)
  return match token with
  | .boundary | .eof => .stop token
  | .closeAngle => if depth = 0 then .stop token else .advance token (depth - 1)
  | .openAngle => .advance token (depth + 1)
  | .other => .advance token depth

def projectThroughStop (input : Input) (context : USize) (index depth : Nat)
    (reversed : List TypeArguments.Token) : Nat → IO (List TypeArguments.Token)
  | 0 => pure reversed.reverse
  | fuel + 1 => do
    match ← projectionStep input context index depth with
    | .stop token => return (token :: reversed).reverse
    | .advance token nextDepth => projectThroughStop input context (index + 1) nextDepth (token :: reversed) fuel

@[export kswiftk_lean_consume_type_arguments]
def consumeFrom (context count : USize) : IO UInt64 := do
  let input := callbackInput context count
  if input.get 0 != .openAngle then return 0
  let tokens ← projectThroughStop input context 1 0 [.openAngle] input.count
  let result := TypeArguments.parse tokens
  let stop : Nat := match result.stop with
    | .missingOpen => 0
    | .closed => 1
    | .recovery => 2
    | .eof => 3
  return ((tokens.length - result.remaining.length) * 4 + stop).toUInt64

end ParserProofs.TypeArgumentConsumption
