import ParserProofs.TypeArguments

set_option warningAsError true

namespace ParserProofs.TypeArgumentConsumption

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

end ParserProofs.TypeArgumentConsumption
