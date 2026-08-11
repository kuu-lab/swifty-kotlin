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

/// Bundled stdlib sources share the AST arena with the test input, so expression
/// scans must skip expressions that originate from bundled `.kt` files.
func isUserSourceExpr(_ id: ExprID, in ctx: CompilationContext) -> Bool {
    guard let ast = ctx.ast, let range = ast.arena.exprRange(id) else { return false }
    return ctx.sourceManager.origin(of: range.start.file)?.isBundledStdlib != true
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
