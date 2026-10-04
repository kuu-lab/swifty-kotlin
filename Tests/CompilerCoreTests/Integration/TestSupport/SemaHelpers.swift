@testable import CompilerCore

func makeSema(
    source: String = "fun noop() {}"
) throws -> (SemaModule, StringInterner) {
    var result: (SemaModule, StringInterner)?
    try withTemporaryFile(contents: source) { path in
        let ctx = makeCompilationContext(inputs: [path])
        try runSema(ctx)
        let sema = try requireTestValue(ctx.sema, "Expected sema module after running Sema")
        result = (sema, ctx.interner)
    }
    return try requireTestValue(result, "Expected makeSema result")
}

/// Compile `sources` together as one module through Sema and hand back the
/// context. Suites that share one context across many `@Test` functions should
/// hold the result in a `static let`, whose `swift_once` initialization compiles
/// the bundled stdlib exactly once even though swift-testing runs those tests
/// concurrently.
func semaContext(for sources: [String]) throws -> CompilationContext {
    var result: CompilationContext?
    try withTemporaryFiles(contents: sources) { paths in
        let ctx = makeCompilationContext(inputs: paths)
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
