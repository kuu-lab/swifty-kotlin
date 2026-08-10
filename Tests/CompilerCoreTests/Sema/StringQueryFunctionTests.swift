@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-031/066: Consolidated Sema coverage for `String.isNullOrEmpty()`,
/// `String.single()`, `String.singleOrNull()`, and `CharSequence.lastIndexOf`.
/// A single Sema pass resolves all source packages and each `do` block verifies
/// the expected symbol/call bindings.
@Suite
struct StringQueryFunctionTests {
    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func allExprIDsInPath(
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

    @Test
    func testStringQueryFunctionsResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0
            fun singleOf(s: String): Char {
                return s.single()
            }

            fun singleOfLiteral(): Char {
                return "x".single()
            }

            fun singleInBranch(s: String, take: Boolean): Char {
                return if (take) s.single() else "y".single()
            }

            fun callsBoth(s: String): Char {
                val a = s.single()
                val b = "z".single()
                return if (a == b) a else b
            }
            """,
            """
            package sample1
            fun String.findDelimiter(delimiter: String): Int {
                return indexOf(delimiter)
            }

            fun lastChar(value: String): Int {
                return value.lastIndexOf('l')
            }

            fun findChar(value: CharSequence): Int {
                return value.lastIndexOf('o', 10, false)
            }

            fun findCharIgnoreCase(value: String): Int {
                return value.lastIndexOf('O', 10, true)
            }

            fun probe(value: CharSequence): Int {
                return value.lastIndexOf('z', 0, false)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let names = ["single", "lastIndexOf"]
            for (index, name) in names.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                let errors = pathDiagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected \(name) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // === single / singleOrNull ===
            do {
                let singleFq = ["kotlin", "text", "single"].map { interner.intern($0) }
                let singleSymbol = try #require(sema.symbols.lookupAll(fqName: singleFq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes.isEmpty
                })
                #expect(sema.symbols.externalLinkName(for: singleSymbol) == nil, "single should be source-backed")
                #expect(sema.symbols.symbol(singleSymbol)?.flags.contains(.synthetic) == false, "single should not be synthetic")
                #expect(sema.symbols.functionSignature(for: singleSymbol)?.returnType == sema.types.charType, "single should return Char")

                let singleOrNullFq = ["kotlin", "text", "singleOrNull"].map { interner.intern($0) }
                let singleOrNullSymbol = try #require(sema.symbols.lookupAll(fqName: singleOrNullFq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes.isEmpty
                })
                #expect(sema.symbols.externalLinkName(for: singleOrNullSymbol) == nil, "singleOrNull should be source-backed")
                #expect(sema.symbols.symbol(singleOrNullSymbol)?.flags.contains(.synthetic) == false, "singleOrNull should not be synthetic")
                #expect(
                    sema.symbols.functionSignature(for: singleOrNullSymbol)?.returnType == sema.types.makeNullable(sema.types.charType),
                    "singleOrNull should return Char?"
                )
            }

            // === lastIndexOf ===
            do {
                let path = paths[1]
                let lastIndexOfCalls = allExprIDsInPath(in: ast, path: path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "lastIndexOf"
                }
                #expect(lastIndexOfCalls.count == 4, "Expected four lastIndexOf calls in sample1")

                for callExpr in lastIndexOfCalls {
                    #expect(
                        sema.bindings.exprTypes[callExpr] == sema.types.intType,
                        "lastIndexOf must return Int"
                    )
                }
            }
        }
    }
}
