import ParserProofs.Runtime.FileLoop

namespace TypeArguments.FFI

example : encodeTopLevelDispatch (directTopLevelDispatch (decodeKind 63)) = 2 := by decide

example :
    enumBodyStartsDeclaration ⟨2, fun index =>
      if index = 0 then { kind := .companionKeyword } else { kind := .objectKeyword }⟩
      0 (pure .notDeclaration) = pure true := by rfl

end TypeArguments.FFI
