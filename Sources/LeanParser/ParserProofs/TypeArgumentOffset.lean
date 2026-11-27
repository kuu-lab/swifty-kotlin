import ParserProofs.TypeArgumentStart

set_option warningAsError true

namespace ParserProofs.TypeArgumentOffset
open TypeArgumentStart

structure GroupDepth where
  paren : Nat := 0
  bracket : Nat := 0
  brace : Nat := 0
  template : Nat := 0

def GroupDepth.isNested (depth : GroupDepth) : Bool :=
  depth.paren > 0 || depth.bracket > 0 || depth.brace > 0 || depth.template > 0

def GroupDepth.step (depth : GroupDepth) : Kind → GroupDepth
  | .openParen => { depth with paren := depth.paren + 1 }
  | .closeParen => { depth with paren := depth.paren - 1 }
  | .openBracket => { depth with bracket := depth.bracket + 1 }
  | .closeBracket => { depth with bracket := depth.bracket - 1 }
  | .openBrace => { depth with brace := depth.brace + 1 }
  | .closeBrace => { depth with brace := depth.brace - 1 }
  | .templateStart => { depth with template := depth.template + 1 }
  | .templateEnd => { depth with template := depth.template - 1 }
  | _ => depth

inductive AngleStep where
  | eof
  | closed
  | advance (angles : Int) (depth : GroupDepth)

def angleStep (kind : Kind) (angles : Int) (depth : GroupDepth) : AngleStep :=
  if kind == .eof then .eof
  else if depth.isNested then .advance angles (depth.step kind)
  else match kind with
    | .openAngle => .advance (angles + 1) depth
    | .closeAngle => if angles == 1 then .closed else .advance (angles - 1) depth
    | _ => .advance angles (depth.step kind)

def skipAngles (input : Input) (index : Nat) (angles : Int) (depth : GroupDepth) : Nat → Nat
  | 0 => index
  | n + 1 =>
    match angleStep (input.get index) angles depth with
    | .eof => index
    | .closed => index + 1
    | .advance angles depth => skipAngles input (index + 1) angles depth n

def offsetPastAngles (input : Input) (start : Nat) : Nat :=
  skipAngles input start 0 {} (input.count - start + 1)

theorem skipAnglesStopsAtOuterClose
    (close : input.get index = .closeAngle) :
    skipAngles input index 1 {} (fuel + 1) = index + 1 := by
  simp [skipAngles, angleStep, close, GroupDepth.isNested]

theorem skipAnglesIgnoresCloseInExpressionGroup
    (close : input.get index = .closeAngle) (nested : depth.isNested = true) :
    skipAngles input index angles depth (fuel + 1) =
      skipAngles input (index + 1) angles depth fuel := by
  simp [skipAngles, angleStep, close, nested, GroupDepth.step]

theorem skipAnglesContinuesPastInnerClose
    (close : input.get index = .closeAngle)
    (outerExpression : depth.isNested = false) (innerAngles : angles ≠ 1) :
    skipAngles input index angles depth (fuel + 1) =
      skipAngles input (index + 1) (angles - 1) depth fuel := by
  simp [skipAngles, angleStep, close, outerExpression, innerAngles]

theorem skipAnglesLeavesEOF (eof : input.get index = .eof) :
    skipAngles input index angles depth (fuel + 1) = index := by
  simp [skipAngles, angleStep, eof]

inductive AngleScanPath (input : Input) :
    Nat → Int → GroupDepth → Nat → Int → GroupDepth → Prop where
  | empty : AngleScanPath input index angles depth 0 angles depth
  | next (step : angleStep (input.get index) angles depth = .advance nextAngles nextDepth)
      (rest : AngleScanPath input (index + 1) nextAngles nextDepth steps lastAngles lastDepth) :
      AngleScanPath input index angles depth (steps + 1) lastAngles lastDepth

theorem skipAnglesThroughPath
    (path : AngleScanPath input index angles depth steps lastAngles lastDepth) :
    skipAngles input index angles depth (steps + work) =
      skipAngles input (index + steps) lastAngles lastDepth work := by
  induction path with
  | empty => simp
  | @next index angles depth nextAngles nextDepth steps lastAngles lastDepth step rest ih =>
    simpa [Nat.add_right_comm steps 1 work, Nat.add_right_comm index 1 steps, skipAngles, step] using ih

theorem skipAnglesDoesNotPassEOF
    (input : Input) (eofIndex : Nat) (eof : input.get eofIndex = .eof)
    (fuel index : Nat) (angles : Int) (depth : GroupDepth) (before : index ≤ eofIndex) :
    skipAngles input index angles depth fuel ≤ eofIndex := by
  induction fuel generalizing index angles depth with
  | zero => simpa [skipAngles] using before
  | succ fuel ih =>
    rcases Nat.eq_or_lt_of_le before with equal | earlier
    · cases equal
      simp [skipAngles, angleStep, eof]
    · cases step : angleStep (input.get index) angles depth with
      | eof => simpa [skipAngles, step] using before
      | closed => simpa [skipAngles, step] using (Nat.succ_le_of_lt earlier)
      | advance nextAngles nextDepth =>
        simpa [skipAngles, step] using ih (index + 1) nextAngles nextDepth (Nat.succ_le_of_lt earlier)

@[export kswiftk_lean_offset_past_type_arguments]
def offsetFrom (context count start : USize) : USize :=
  (offsetPastAngles (callbackInput context count) start.toNat).toUSize

end ParserProofs.TypeArgumentOffset
