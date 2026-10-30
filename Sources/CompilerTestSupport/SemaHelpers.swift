@testable import CompilerCore

/// Compile `sources` together as one module through Sema and hand back the
/// context. Suites that share one context across many `@Test` functions should
/// hold the result in a `static let`, whose `swift_once` initialization compiles
/// the bundled stdlib exactly once even though swift-testing runs those tests
/// concurrently.
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
