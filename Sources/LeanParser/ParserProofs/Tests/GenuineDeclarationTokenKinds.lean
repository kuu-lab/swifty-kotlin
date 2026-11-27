import ParserProofs.Runtime.GenuineDeclarations

namespace TypeArguments.FFI

private def declarationTokens (tokens : List LexToken) : Input :=
  { count := tokens.length, read := fun index => tokens[index]?.getD {} }

example : (genuineDeclarationAt (declarationTokens
    [{ kind := .modifier, valueModifier := true }, { kind := .classKeyword },
      { kind := .identifier }]) 0 4).verdict = .declaration := rfl

example : (genuineDeclarationAt (declarationTokens
    [{ kind := .enumKeyword }, { kind := .classKeyword }, { kind := .identifier }]) 0 4).verdict =
    .declaration := rfl

example : (genuineDeclarationAt (declarationTokens
    [{ kind := .companionKeyword }, { kind := .objectKeyword }]) 0 4).verdict = .declaration := rfl

example : (genuineDeclarationAt (declarationTokens
    [{ kind := .companionKeyword }, { kind := .openParen }]) 0 4).verdict = .notDeclaration := rfl

end TypeArguments.FFI
