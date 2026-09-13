@testable import CompilerCore

// Path-scoped counterparts of the whole-arena search helpers in `ASTHelpers.swift`
// and `KIRAndLLVM.swift`. Bundled stdlib sources share one AST arena with the test
// input, and a consolidated test compiles several user sources into that same arena,
// so a search often has to be narrowed to a single source file. `isUserSourceExpr`
// only separates user code from bundled stdlib and cannot tell two user sources
// apart, which is why these take the source `path` explicitly.

/// First expression in `path` matching `predicate`, in arena order.
func firstExprID(
    in ast: ASTModule,
    path: String,
    ctx: CompilationContext,
    where predicate: (ExprID, Expr) -> Bool
) -> ExprID? {
    for index in ast.arena.exprs.indices {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID),
              let range = ast.arena.exprRange(exprID),
              ctx.sourceManager.path(of: range.start.file) == path
        else { continue }
        if predicate(exprID, expr) { return exprID }
    }
    return nil
}

/// Last expression in `path` matching `predicate`, in arena order.
func lastExprID(
    in ast: ASTModule,
    path: String,
    ctx: CompilationContext,
    where predicate: (ExprID, Expr) -> Bool
) -> ExprID? {
    for index in ast.arena.exprs.indices.reversed() {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID),
              let range = ast.arena.exprRange(exprID),
              ctx.sourceManager.path(of: range.start.file) == path
        else { continue }
        if predicate(exprID, expr) { return exprID }
    }
    return nil
}

/// Every expression in `path` matching `predicate`, in arena order.
func allExprIDs(
    in ast: ASTModule,
    path: String,
    ctx: CompilationContext,
    where predicate: (ExprID, Expr) -> Bool
) -> [ExprID] {
    var results: [ExprID] = []
    for index in ast.arena.exprs.indices {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID),
              let range = ast.arena.exprRange(exprID),
              ctx.sourceManager.path(of: range.start.file) == path
        else { continue }
        if predicate(exprID, expr) { results.append(exprID) }
    }
    return results
}

/// Member calls named `name` in `path`.
func memberCallExprIDs(
    named name: String,
    in ast: ASTModule,
    path: String,
    ctx: CompilationContext,
    interner: StringInterner
) -> [ExprID] {
    ast.arena.exprs.indices.compactMap { index in
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID),
              case let .memberCall(_, callee, _, _, range) = expr,
              interner.resolve(callee) == name,
              ctx.sourceManager.path(of: range.start.file) == path
        else {
            return nil
        }
        return exprID
    }
}

/// Declaration backing the first object literal written in `path`.
func firstUserObjectLiteralDeclID(
    in ast: ASTModule,
    path: String,
    sourceManager: SourceManager
) -> DeclID? {
    for index in ast.arena.exprs.indices {
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID),
              case let .objectLiteral(_, declID, _) = expr,
              let declID,
              let range = ast.arena.exprRange(exprID),
              sourceManager.path(of: range.start.file) == path
        else { continue }
        return declID
    }
    return nil
}

/// Statements in the body of `fun main` declared in `path`.
func findMainBodyStatements(
    in ast: ASTModule,
    path: String,
    sourceManager: SourceManager,
    interner: StringInterner
) -> [ExprID]? {
    guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
    for file in ast.files {
        guard file.fileID == fileID else { continue }
        for declID in file.topLevelDecls {
            guard let decl = ast.arena.decl(declID),
                  case let .funDecl(function) = decl,
                  interner.resolve(function.name) == "main",
                  case let .block(statements, _) = function.body
            else { continue }
            return statements
        }
    }
    return nil
}
