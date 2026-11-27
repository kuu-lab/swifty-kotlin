set_option warningAsError true

namespace TypeArguments

inductive Token where
  | openAngle
  | closeAngle
  | boundary
  | other
  | eof

inductive Stop where
  | missingOpen
  | closed
  | recovery
  | eof

structure Result where
  stop : Stop
  remaining : List Token

def scan (nested : Nat) (tokens : List Token) : Result :=
  match tokens with
  | [] => ⟨.eof, []⟩
  | token :: rest =>
    match token, nested with
    | .eof, _ => ⟨.eof, tokens⟩
    | .boundary, 0 => ⟨.recovery, tokens⟩
    | .closeAngle, 0 => ⟨.closed, rest⟩
    | .openAngle, n => scan (n + 1) rest
    | .closeAngle, n + 1 => scan n rest
    | _, n => scan n rest
termination_by tokens.length

def parse (tokens : List Token) : Result :=
  match tokens with
  | .openAngle :: rest => scan 0 rest
  | _ => ⟨.missingOpen, tokens⟩

inductive ReachesBoundary : Nat → List Token → List Token → Prop where
  | here (suffix : List Token) : ReachesBoundary 0 (.boundary :: suffix) suffix
  | openAngle : ReachesBoundary (n + 1) rest suffix →
      ReachesBoundary n (.openAngle :: rest) suffix
  | closeAngle : ReachesBoundary n rest suffix →
      ReachesBoundary (n + 1) (.closeAngle :: rest) suffix
  | nestedBoundary : ReachesBoundary (n + 1) rest suffix →
      ReachesBoundary (n + 1) (.boundary :: rest) suffix
  | other : ReachesBoundary n rest suffix →
      ReachesBoundary n (.other :: rest) suffix

theorem scanPreservesBoundary (path : ReachesBoundary nested tokens suffix) :
    scan nested tokens = ⟨.recovery, .boundary :: suffix⟩ := by
  induction path with
  | here => simp [scan]
  | openAngle _ ih => simpa [scan] using ih
  | closeAngle _ ih => simpa [scan] using ih
  | nestedBoundary _ ih => simpa [scan] using ih
  | other _ ih => simpa [scan] using ih

theorem parsePreservesBoundary (path : ReachesBoundary 0 tokens suffix) :
    parse (.openAngle :: tokens) = ⟨.recovery, .boundary :: suffix⟩ :=
  scanPreservesBoundary path

theorem scanRecoveryBoundary (stopped : (scan nested tokens).stop = .recovery) :
    ∃ suffix, (scan nested tokens).remaining = .boundary :: suffix ∧
      ReachesBoundary nested tokens suffix := by
  induction nested, tokens using scan.induct with
  | case1 => simp [scan] at stopped
  | case2 => simp [scan] at stopped
  | case3 rest => exact ⟨rest, by simp [scan], .here rest⟩
  | case4 => simp [scan] at stopped
  | case5 rest n ih =>
    simp only [scan] at stopped ⊢
    obtain ⟨suffix, remaining, path⟩ := ih stopped
    exact ⟨suffix, remaining, .openAngle path⟩
  | case6 rest n ih =>
    simp only [scan] at stopped ⊢
    obtain ⟨suffix, remaining, path⟩ := ih stopped
    exact ⟨suffix, remaining, .closeAngle path⟩
  | case7 token rest n _ _ _ _ _ ih =>
    cases token <;> cases n <;> simp_all [scan]
    all_goals
      obtain ⟨suffix, remaining, path⟩ := ih
      exact ⟨suffix, remaining, by first | exact .nestedBoundary path | exact .other path⟩

theorem scanReachesBoundary
    (result : scan nested tokens = ⟨.recovery, .boundary :: suffix⟩) :
    ReachesBoundary nested tokens suffix := by
  obtain ⟨found, remaining, path⟩ := scanRecoveryBoundary (congrArg Result.stop result)
  have sameSuffix := List.cons.inj ((congrArg Result.remaining result).symm.trans remaining)
  rw [sameSuffix.2]
  exact path

theorem parseRecoveryBoundary (stopped : (parse tokens).stop = .recovery) :
    ∃ suffix, (parse tokens).remaining = .boundary :: suffix := by
  cases tokens with
  | nil => simp [parse] at stopped
  | cons token rest =>
    cases token <;> simp [parse] at stopped ⊢
    obtain ⟨suffix, remaining, _⟩ := scanRecoveryBoundary stopped
    exact ⟨suffix, remaining⟩

theorem parseRecoveryIff :
    parse (.openAngle :: tokens) = ⟨.recovery, .boundary :: suffix⟩ ↔
      ReachesBoundary 0 tokens suffix :=
  ⟨scanReachesBoundary, parsePreservesBoundary⟩

theorem scanRemainingIsSuffix (nested : Nat) (tokens : List Token) :
    (scan nested tokens).remaining <:+ tokens := by
  induction nested, tokens using scan.induct with
  | case1 => simp [scan]
  | case2 => simp [scan]
  | case3 => simp [scan]
  | case4 => simp [scan]
  | case5 rest n ih => simpa only [scan] using ih.trans (List.suffix_cons .openAngle rest)
  | case6 rest n ih => simpa only [scan] using ih.trans (List.suffix_cons .closeAngle rest)
  | case7 token rest n _ _ _ _ _ ih =>
    have suffix := ih.trans (List.suffix_cons token rest)
    cases token <;> cases n <;> simp_all [scan]

theorem parseRemainingIsSuffix (tokens : List Token) :
    (parse tokens).remaining <:+ tokens := by
  cases tokens with
  | nil => simp [parse]
  | cons token rest =>
    cases token <;> simp [parse]
    exact (scanRemainingIsSuffix 0 rest).trans (List.suffix_cons .openAngle rest)

inductive ScansPrefix : Nat → List Token → Nat → Prop where
  | empty : ScansPrefix n [] n
  | openAngle : ScansPrefix (n + 1) rest final → ScansPrefix n (.openAngle :: rest) final
  | closeAngle : ScansPrefix n rest final → ScansPrefix (n + 1) (.closeAngle :: rest) final
  | nestedBoundary : ScansPrefix (n + 1) rest final →
      ScansPrefix (n + 1) (.boundary :: rest) final
  | other : ScansPrefix n rest final → ScansPrefix n (.other :: rest) final

theorem scanAfterPrefix (path : ScansPrefix nested consumed final) (tail : List Token) :
    scan nested (consumed ++ tail) = scan final tail := by
  induction path with
  | empty => rfl
  | openAngle _ ih => simpa [scan] using ih
  | closeAngle _ ih => simpa [scan] using ih
  | nestedBoundary _ ih => simpa [scan] using ih
  | other _ ih => simpa [scan] using ih

theorem scanClosedPrefix (result : scan nested tokens = ⟨.closed, suffix⟩) :
    ∃ consumed, tokens = consumed ++ (.closeAngle :: suffix) ∧ ScansPrefix nested consumed 0 := by
  induction nested, tokens using scan.induct with
  | case1 => simp [scan] at result
  | case2 => simp [scan] at result
  | case3 => simp [scan] at result
  | case4 rest =>
    have remaining : rest = suffix := by simpa [scan] using result
    exact ⟨[], by simp [remaining], .empty⟩
  | case5 rest n ih =>
    obtain ⟨consumed, split, path⟩ := ih (by simpa only [scan] using result)
    exact ⟨.openAngle :: consumed, by simp [split], .openAngle path⟩
  | case6 rest n ih =>
    obtain ⟨consumed, split, path⟩ := ih (by simpa only [scan] using result)
    exact ⟨.closeAngle :: consumed, by simp [split], .closeAngle path⟩
  | case7 token rest n _ _ _ _ _ ih =>
    cases token <;> cases n <;> simp_all [scan]
    case boundary.succ =>
      obtain ⟨consumed, split, path⟩ := ih
      exact ⟨.boundary :: consumed, by simp [split], .nestedBoundary path⟩
    all_goals
      obtain ⟨consumed, split, path⟩ := ih
      exact ⟨.other :: consumed, by simp [split], .other path⟩

theorem parseClosedIff :
    parse (.openAngle :: tokens) = ⟨.closed, suffix⟩ ↔
      ∃ consumed, tokens = consumed ++ (.closeAngle :: suffix) ∧ ScansPrefix 0 consumed 0 := by
  constructor
  · exact scanClosedPrefix
  · rintro ⟨consumed, rfl, path⟩
    change scan 0 (consumed ++ (.closeAngle :: suffix)) = ⟨.closed, suffix⟩
    rw [scanAfterPrefix path]
    simp [scan]

theorem scanPreservesEOF (nested : Nat) (beforeEOF suffix : List Token) :
    (.eof :: suffix) <:+ (scan nested (beforeEOF ++ (.eof :: suffix))).remaining := by
  induction beforeEOF generalizing nested with
  | nil => simp [scan]
  | cons token beforeEOF ih =>
    have inputSuffix := List.suffix_append beforeEOF (.eof :: suffix)
    have inputConsSuffix := inputSuffix.trans (List.suffix_cons token (beforeEOF ++ (.eof :: suffix)))
    cases token <;> cases nested <;> simp_all [scan]

theorem parsePreservesEOF (beforeEOF suffix : List Token) :
    (.eof :: suffix) <:+ (parse (beforeEOF ++ (.eof :: suffix))).remaining := by
  cases beforeEOF with
  | nil => simp [parse]
  | cons token beforeEOF =>
    have inputSuffix := List.suffix_append beforeEOF (.eof :: suffix)
    have inputConsSuffix := inputSuffix.trans (List.suffix_cons token (beforeEOF ++ (.eof :: suffix)))
    cases token <;> simp_all [parse]
    exact scanPreservesEOF 0 beforeEOF suffix

end TypeArguments
