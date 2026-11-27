import ParserProofs.Runtime.TokenInput

namespace TypeArguments.FFI

private def modifierContext (follower : Kind) : Input :=
  { count := 3
    read := fun
      | 0 => { kind := .modifier }
      | 1 => { kind := .context }
      | 2 => { kind := follower }
      | _ => {} }

example : (modifierDeclarationAt (modifierContext .colon) 0 2).1 = false := by decide

example : (modifierDeclarationAt (modifierContext .openParen) 0 2).1 = true := by decide

end TypeArguments.FFI
