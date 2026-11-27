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

def projectionNext (token : TypeArguments.Token) (depth : Nat) : Option Nat :=
  match token with
  | .eof => none
  | .boundary => if depth = 0 then none else some depth
  | .closeAngle => if depth = 0 then none else some (depth - 1)
  | .openAngle => some (depth + 1)
  | .other => some depth

def truncateAtProjectionStop (depth : Nat) : List TypeArguments.Token → List TypeArguments.Token
  | [] => []
  | token :: rest =>
    match projectionNext token depth with
    | none => [token]
    | some next => token :: truncateAtProjectionStop next rest

theorem projectionStopMatchesScan (stopped : projectionNext token depth = none) :
    TypeArguments.scan depth (token :: rest) =
      ⟨(TypeArguments.scan depth [token]).stop, (TypeArguments.scan depth [token]).remaining ++ rest⟩ := by
  cases depth <;> cases token <;> simp_all [projectionNext, TypeArguments.scan]

theorem projectionAdvanceMatchesScan (advanced : projectionNext token depth = some next) :
    TypeArguments.scan depth (token :: rest) = TypeArguments.scan next rest := by
  cases depth <;> cases token <;> simp_all [projectionNext, TypeArguments.scan]
  case succ.boundary =>
    rw [← advanced]
    simp [TypeArguments.scan]

theorem truncationPreservesScan (depth : Nat) (tokens : List TypeArguments.Token) :
    let truncated := truncateAtProjectionStop depth tokens
    ∃ unread, tokens = truncated ++ unread ∧
      TypeArguments.scan depth tokens =
        ⟨(TypeArguments.scan depth truncated).stop, (TypeArguments.scan depth truncated).remaining ++ unread⟩ := by
  induction tokens generalizing depth with
  | nil => exact ⟨[], by simp [truncateAtProjectionStop], by simp [truncateAtProjectionStop, TypeArguments.scan]⟩
  | cons token rest ih =>
    cases step : projectionNext token depth with
    | none =>
      exact ⟨rest, by simp [truncateAtProjectionStop, step],
        by simpa [truncateAtProjectionStop, step] using projectionStopMatchesScan (rest := rest) step⟩
    | some next =>
      obtain ⟨unread, suffix, result⟩ := ih next
      refine ⟨unread, ?_, ?_⟩
      · simpa [truncateAtProjectionStop, step] using congrArg (List.cons token) suffix
      · simp only [truncateAtProjectionStop, step, projectionAdvanceMatchesScan step]
        exact result

@[noinline]
def projectionStep (input : Input) (context : USize) (index depth : Nat) :
    IO (TypeArguments.Token × Option Nat) := do
  let token ← projectToken (readBoundary context index.toUSize) depth (input.get index)
  return (token, projectionNext token depth)

def projectThroughStop (input : Input) (context : USize) (index depth : Nat)
    (reversed : List TypeArguments.Token) : Nat → IO (List TypeArguments.Token)
  | 0 => pure reversed.reverse
  | fuel + 1 => do
    let (token, next) ← projectionStep input context index depth
    match next with
    | none => return (token :: reversed).reverse
    | some nextDepth => projectThroughStop input context (index + 1) nextDepth (token :: reversed) fuel

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
