@testable import CompilerCore

func semaContext(for sources: [String]) throws -> CompilationContext {
    var result: CompilationContext?
    try withTemporaryFiles(contents: sources) { paths in
        let ctx = makeCompilationContext(inputs: paths, allowDefaultStdlibLibrary: false)
        try runSema(ctx)
        result = ctx
    }
    return try requireTestValue(result, "Expected a compilation context after running Sema")
}

func memberCallExprIDs(
    named name: String,
    in ast: ASTModule,
    interner: StringInterner
) -> [ExprID] {
    ast.arena.exprs.indices.compactMap { index in
        let exprID = ExprID(rawValue: Int32(index))
        guard let expr = ast.arena.expr(exprID),
              case let .memberCall(_, callee, _, _, _) = expr,
              interner.resolve(callee) == name
        else {
            return nil
        }
        return exprID
    }
}
