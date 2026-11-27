import ParserProofs.Runtime.DeclarationPrefixes

namespace TypeArguments.FFI

private def prefixFollowedBy (kind : Kind) : Input :=
  { count := 2, read := fun
    | 0 => { kind := .modifier }
    | 1 => { kind }
    | _ => {} }

example : scanLeadingPrefix (prefixFollowedBy .funKeyword) .declaration 0 1 =
    some ⟨.closed, 1⟩ := rfl

example : scanLeadingPrefix (prefixFollowedBy .eof) .declaration 0 1 =
    some ⟨.eof, 1⟩ := rfl

example : scanLeadingPrefix (prefixFollowedBy .modifier) .declaration 0 1 = none := rfl

end TypeArguments.FFI
