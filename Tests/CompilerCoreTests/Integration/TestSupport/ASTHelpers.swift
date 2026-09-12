@testable import CompilerCore

/// Walk every top-level declaration of `ast` in declaration order and return the
/// first one `transform` accepts. Stops at the first match, so callers pay only
/// for the prefix they need -- bundled stdlib sources share the arena and make a
/// full scan expensive.
private func firstTopLevelDecl<T>(
    in ast: ASTModule,
    matching transform: (Decl) -> T?
) -> T? {
    for file in ast.files {
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID),
                  let match = transform(decl)
            else {
                continue
            }
            return match
        }
    }
    return nil
}

/// Search for a top-level function declaration by name in the given AST module.
func topLevelFunction(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> FunDecl? {
    firstTopLevelDecl(in: ast) { decl in
        guard case let .funDecl(function) = decl,
              interner.resolve(function.name) == name
        else {
            return nil
        }
        return function
    }
}

/// Search for a top-level property declaration by name in the given AST module.
func topLevelProperty(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> PropertyDecl? {
    firstTopLevelDecl(in: ast) { decl in
        guard case let .propertyDecl(property) = decl,
              interner.resolve(property.name) == name
        else {
            return nil
        }
        return property
    }
}

/// Search for a property declared as a member of the named class.
func memberProperty(
    named name: String,
    ofClass className: String,
    in ast: ASTModule,
    interner: StringInterner
) -> PropertyDecl? {
    firstTopLevelDecl(in: ast) { decl in
        guard case let .classDecl(classDecl) = decl,
              interner.resolve(classDecl.name) == className
        else {
            return nil
        }
        for propertyDeclID in classDecl.memberProperties {
            guard let propertyDecl = ast.arena.decl(propertyDeclID),
                  case let .propertyDecl(property) = propertyDecl,
                  interner.resolve(property.name) == name
            else {
                continue
            }
            return property
        }
        return nil
    }
}

/// Whether `fileID` names one of the bundled stdlib `.kt` sources rather than a
/// test input. Prefer this over matching on the synthetic path prefix, which is
/// an implementation detail of ``SourceManager``.
func isBundledStdlibFile(_ fileID: FileID, in ctx: CompilationContext) -> Bool {
    ctx.sourceManager.origin(of: fileID)?.isBundledStdlib == true
}

/// Bundled stdlib sources share the AST arena with the test input, so expression
/// scans must skip expressions that originate from bundled `.kt` files.
func isUserSourceExpr(_ id: ExprID, in ctx: CompilationContext) -> Bool {
    guard let ast = ctx.ast, let range = ast.arena.exprRange(id) else { return false }
    return !isBundledStdlibFile(range.start.file, in: ctx)
}
