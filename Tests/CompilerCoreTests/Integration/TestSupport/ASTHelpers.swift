@testable import CompilerCore

/// Search for a top-level function declaration by name in the given AST module.
func topLevelFunction(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> FunDecl? {
    for file in ast.files {
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID),
                  case let .funDecl(function) = decl
            else {
                continue
            }
            if interner.resolve(function.name) == name {
                return function
            }
        }
    }
    return nil
}

/// Search for a top-level property declaration by name in the given AST module.
func topLevelProperty(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> PropertyDecl? {
    for file in ast.files {
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID),
                  case let .propertyDecl(property) = decl
            else {
                continue
            }
            if interner.resolve(property.name) == name {
                return property
            }
        }
    }
    return nil
}
