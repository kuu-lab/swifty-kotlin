import Lean
import ParserProofs.TypeArguments

set_option warningAsError true

namespace TypeArguments

private def stopName : Stop → String
  | .missingOpen => "missingOpen"
  | .closed => "closed"
  | .recovery => "recovery"
  | .eof => "eof"

private structure SpelledToken where
  source : String
  token : Token

private def alphabet : List SpelledToken :=
  [⟨" <", .openAngle⟩, ⟨" >", .closeAngle⟩, ⟨" T", .other⟩,
   ⟨"\nfun", .boundary⟩, ⟨"\nT", .other⟩]

private def allOfLength : Nat → List (List SpelledToken)
  | 0 => [[]]
  | n + 1 => alphabet.flatMap fun token => (allOfLength n).map (token :: ·)

private def additionalCases : List (String × List Token) :=
  [("", []),
   (" T", [.other]),
   ("\nfun f()", [.boundary, .other, .other, .other]),
   ("<Map<K, V>> Tail", [.openAngle, .other, .openAngle, .other, .other, .other,
                         .closeAngle, .closeAngle, .other]),
   ("<T fun", [.openAngle, .other, .other]),
   ("<T\nprivate val x = 1", [.openAngle, .other, .boundary, .other, .other, .other, .other]),
   ("<T\ncontext(x: T) fun f()", [.openAngle, .other, .boundary, .other, .other,
                                  .other, .other, .other, .other, .other, .other, .other]),
   ("<T,\ncontext: U>", [.openAngle, .other, .other, .other, .other, .other, .closeAngle]),
   ("<T\n@A\nprivate val x = 1", [.openAngle, .other, .boundary, .other, .boundary,
                                  .other, .other, .other, .other]),
   ("<T,\n@A(1)\nP>", [.openAngle, .other, .other, .other, .other, .other,
                         .other, .other, .other, .closeAngle])]

def oracle : List Lean.Json :=
  let generated := (List.range 5).flatMap allOfLength |>.map fun body =>
    ("<" ++ String.join (body.map (·.source)), .openAngle :: body.map (·.token))
  (generated ++ additionalCases).map fun (source, body) =>
    let tokens := body ++ [.eof]
    let result := parse tokens
    Lean.Json.mkObj
      [("source", Lean.toJson source), ("tokenCount", Lean.toJson tokens.length),
       ("consumed", Lean.toJson (tokens.length - result.remaining.length)),
       ("stop", Lean.toJson (stopName result.stop))]

end TypeArguments

def main : IO Unit :=
  IO.println (Lean.Json.arr TypeArguments.oracle.toArray).compress
