import ParserProofs.Runtime.TypeArgumentScans

namespace TypeArguments.FFI

private def recoveryInput (leading : List LexToken) (declaration : List LexToken) : Input :=
  let tokens := leading ++ declaration
  ⟨tokens.length, fun index => tokens[index]?.getD {}⟩

private def stopsBeforeDeclaration (tokens : List LexToken) : Bool :=
  let leading : List LexToken := [{ kind := .openAngle }, { kind := .identifier }]
  let input := recoveryInput leading tokens
  let (projected, _) := projectThroughStop input 8 1 0 [.openAngle] {} (input.count + 1)
  match TypeArguments.parse projected with
  | ⟨.recovery, [.boundary]⟩ => projected.length == leading.length + 1
  | _ => false

#guard
    ([
      [{ kind := .classKeyword, newline := true }, { kind := .identifier }],
      [{ kind := .modifier, newline := true }, { kind := .classKeyword }, { kind := .identifier }]
    ] : List (List LexToken)).all stopsBeforeDeclaration == true

end TypeArguments.FFI
