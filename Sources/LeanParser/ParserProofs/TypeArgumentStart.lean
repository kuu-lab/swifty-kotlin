set_option warningAsError true

namespace ParserProofs.TypeArgumentStart

inductive Kind where
  | other | openAngle | closeAngle | at | dot | colon
  | openParen | closeParen | openBracket | closeBracket | openBrace | closeBrace
  | templateStart | templateEnd | varianceIn | eof
  | identifier | star | varianceOut | comma | question | questionDot | doubleColon
  | forKeyword | whileKeyword | doKeyword | arrow
  | bang | bangBang | questionColon | ampAmp | barBar | isKeyword | asKeyword | objectKeyword | fieldKeyword | assign | context | modifier
  | softWhenKeyword | catchKeyword | companionKeyword | constructorKeyword | dynamicKeyword
  | enumKeyword | finallyKeyword | importKeyword | reifiedKeyword
  deriving DecidableEq

structure Input where
  count : Nat
  get : Nat → Kind

def decodeKind : UInt8 → Kind
  | 1 => .openAngle | 2 => .closeAngle | 3 => .at | 4 => .dot | 5 => .colon
  | 6 => .openParen | 7 => .closeParen | 8 => .openBracket | 9 => .closeBracket
  | 10 => .openBrace | 11 => .closeBrace | 12 => .templateStart | 13 => .templateEnd
  | 14 => .varianceIn | 15 => .eof | 16 => .identifier | 17 => .star
  | 18 => .varianceOut | 19 => .comma | 20 => .question | 21 => .questionDot | 22 => .doubleColon
  | 23 => .forKeyword | 24 => .whileKeyword | 25 => .doKeyword | 26 => .arrow
  | 27 => .bang | 28 => .bangBang | 29 => .questionColon | 30 => .ampAmp
  | 31 => .barBar | 32 => .isKeyword | 33 => .asKeyword | 34 => .objectKeyword | 35 => .fieldKeyword | 36 => .assign | 37 => .context | 38 => .modifier
  | 39 => .softWhenKeyword | 40 => .catchKeyword | 41 => .companionKeyword
  | 42 => .constructorKeyword | 43 => .dynamicKeyword | 44 => .enumKeyword
  | 45 => .finallyKeyword | 46 => .importKeyword | 47 => .reifiedKeyword
  | _ => .other

@[extern "kswiftk_lean_read_parser_token"]
opaque readToken (context index : USize) : UInt8

def callbackInput (context count : USize) : Input :=
  ⟨count.toNat, fun index => if index < count.toNat then decodeKind (readToken context index.toUSize) else .eof⟩

def isVariance : Kind → Bool
  | .varianceIn | .varianceOut => true
  | _ => false

def canStartLookahead (input : Input) (index nested : Nat)
    (expected sawProjection previousVariance : Bool) : Nat → Bool
  | 0 => false
  | fuel + 1 =>
    let kind := input.get index
    match kind with
    | .eof => nested == 0 && sawProjection && !expected
    | .openAngle => canStartLookahead input (index + 1) (nested + 1) expected sawProjection false fuel
    | .closeAngle =>
      if nested == 0 then sawProjection && !previousVariance
      else canStartLookahead input (index + 1) (nested - 1) expected sawProjection false fuel
    | _ =>
      let variance := isVariance kind
      if nested != 0 then
        canStartLookahead input (index + 1) nested expected sawProjection variance fuel
      else match kind with
        | .comma =>
          sawProjection && !expected &&
            canStartLookahead input (index + 1) nested true sawProjection false fuel
        | .identifier | .star =>
          canStartLookahead input (index + 1) nested false true false fuel
        | .varianceIn | .varianceOut =>
          canStartLookahead input (index + 1) nested true sawProjection true fuel
        | .dot | .question | .questionDot | .doubleColon | .colon =>
          !expected && canStartLookahead input (index + 1) nested expected sawProjection false fuel
        | _ => canStartLookahead input (index + 1) nested expected sawProjection false fuel
termination_by structural fuel => fuel

def canStart (input : Input) (start : Nat) (hasAnchor : Bool) : Bool :=
  hasAnchor && input.get start == .openAngle &&
    canStartLookahead input (start + 1) 0 true false false (input.count - start + 1)

theorem canStartAcceptsOuterTrailingComma
    (comma : input.get index = .comma)
    (close : input.get (index + 1) = .closeAngle) :
    canStartLookahead input index 0 false true previousVariance (fuel + 2) = true := by
  simp [canStartLookahead, comma, close]

theorem canStartRejectsEmptyList
    (opening : input.get start = .openAngle)
    (close : input.get (start + 1) = .closeAngle) :
    canStart input start hasAnchor = false := by
  simp [canStart, canStartLookahead, opening, close]

theorem canStartRejectsOuterConsecutiveCommas
    (first : input.get index = .comma)
    (second : input.get (index + 1) = .comma) :
    canStartLookahead input index 0 expected sawProjection previousVariance (fuel + 2) = false := by
  simp [canStartLookahead, first, second]

theorem canStartRejectsOuterDanglingVariance
    (variance : input.get index = .varianceIn ∨ input.get index = .varianceOut)
    (close : input.get (index + 1) = .closeAngle) :
    canStartLookahead input index 0 expected sawProjection previousVariance (fuel + 2) = false := by
  rcases variance with variance | variance <;> simp [canStartLookahead, variance, close]

@[export kswiftk_lean_can_start_type_arguments]
def canStartFrom (context count : USize) (hasAnchor : UInt8) : UInt8 :=
  if canStart (callbackInput context count) 0 (hasAnchor != 0) then 1 else 0

end ParserProofs.TypeArgumentStart
