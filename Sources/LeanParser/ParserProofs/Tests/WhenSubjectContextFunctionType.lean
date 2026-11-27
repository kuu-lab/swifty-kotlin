import ParserProofs.Runtime.ParameterPrefixes

namespace TypeArguments.FFI

private def subjectWithContext (afterContext : List LexToken) : Input :=
  let tokens : List LexToken :=
    [{ kind := .declaration, valKeyword := true },
      { kind := .identifier, identifierLike := true }, { kind := .colon },
      { kind := .context, newline := true }, { kind := .openParen },
      { kind := .identifier }, { kind := .closeParen }] ++ afterContext
  { count := tokens.length, read := fun index => tokens[index]?.getD {} }

example :
    (match whenSubjectPrefixLookahead (subjectWithContext
      [{ kind := .openParen }, { kind := .closeParen }, { kind := .arrow },
        { kind := .identifier }, { kind := .assign }, { kind := .identifier },
        { kind := .closeParen }]) 0 12 with
    | (.found 11, []) => true
    | _ => false) = true := by decide

example :
    (match whenSubjectPrefixLookahead (subjectWithContext
      [{ kind := .funKeyword }, { kind := .identifier }, { kind := .openParen },
        { kind := .closeParen }, { kind := .assign }]) 0 12 with
    | (.declarationBoundary, []) => true
    | _ => false) = true := by decide

end TypeArguments.FFI
