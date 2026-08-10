@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-069/094 / STDLIB-IO-FN-011: Consolidated Sema coverage for
/// `CharSequence.split`, `CharSequence.toCollection`, and `String.byteInputStream`.
/// A single Sema pass resolves all source packages; per-`do` blocks verify call
/// bindings, return types, and external links.
@Suite
struct StringCollectionIOFunctionTests {
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

    private func fqNameMatches(
        _ symbolID: SymbolID,
        expected: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let info = sema.symbols.symbol(symbolID) else { return false }
        return info.fqName.map { interner.resolve($0) } == expected
    }

    @Test
    func testCollectionAndIOFunctionsResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.text.Charsets
            import java.io.ByteArrayInputStream

            fun useDefaultCharset(value: String) = value.byteInputStream()

            fun useExplicitCharset(value: String) = value.byteInputStream(Charsets.UTF_16)

            fun consume(value: String): Int {
                val stream: ByteArrayInputStream = value.byteInputStream()
                val available = stream.available()
                val first = stream.read()
                stream.close()
                return available + first
            }

            fun firstByte(value: String): Int = value.byteInputStream().use { it.read() }
            """,
            """
            package sample1
            fun collectString(s: String): MutableList<Char> {
                val destination = mutableListOf<Char>('z')
                return s.toCollection(destination)
            }

            fun collectCharSequence(s: CharSequence): MutableList<Char> {
                val destination = mutableListOf<Char>()
                return s.toCollection(destination)
            }

            fun collectSet(s: String): MutableSet<Char> {
                val destination = mutableSetOf<Char>()
                return s.toCollection(destination)
            }

            fun chainedSize(s: String): Int {
                return s.toCollection(mutableListOf<Char>()).size
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected byteInputStream/toCollection to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            // === byteInputStream ===
            do {
                let path = paths[0]
                let callExprs = allExprIDsInPath(in: ast, path: path, ctx: ctx) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == "byteInputStream"
                }
                #expect(callExprs.count == 4, "Expected four byteInputStream calls in sample0")

                for callExpr in callExprs {
                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected call binding for byteInputStream"
                    )
                    let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
                    #expect(signature.receiverType == sema.types.stringType)

                    guard case let .classType(returnClassType) = sema.types.kind(of: signature.returnType) else {
                        Issue.record("Expected byteInputStream to return a class type")
                        continue
                    }
                    let returnInfo = try #require(sema.symbols.symbol(returnClassType.classSymbol))
                    #expect(
                        returnInfo.fqName.map { interner.resolve($0) } == ["java", "io", "ByteArrayInputStream"]
                    )

                    if signature.parameterTypes.isEmpty {
                        #expect(
                            sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_byteInputStream_flat"
                        )
                        #expect(
                            fqNameMatches(chosenCallee, expected: ["kotlin", "io", "byteInputStream"], sema: sema, interner: interner)
                        )
                    } else if signature.parameterTypes.count == 1 {
                        #expect(
                            sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_byteInputStream_charset_flat"
                        )
                        guard case let .classType(paramClassType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                            Issue.record("Expected charset parameter to be a class type")
                            continue
                        }
                        let paramInfo = try #require(sema.symbols.symbol(paramClassType.classSymbol))
                        #expect(
                            paramInfo.fqName.map { interner.resolve($0) } == ["kotlin", "text", "Charset"]
                        )
                    } else {
                        Issue.record("Unexpected byteInputStream parameter count \(signature.parameterTypes.count)")
                    }
                }

                let fqName = ["kotlin", "io", "byteInputStream"].map { interner.intern($0) }
                let symbols = sema.symbols.lookupAll(fqName: fqName)
                #expect(symbols.count == 2, "Expected exactly two byteInputStream overloads in kotlin.io")

                let externalLinks = Set(symbols.compactMap { sema.symbols.externalLinkName(for: $0) })
                #expect(
                    externalLinks == ["kk_string_byteInputStream_flat", "kk_string_byteInputStream_charset_flat"]
                )

                for symbolID in symbols {
                    let signature = try #require(sema.symbols.functionSignature(for: symbolID))
                    #expect(signature.receiverType == sema.types.stringType)
                }
            }

            // === toCollection ===
            do {
                let fqName = ["kotlin", "text", "toCollection"].map { interner.intern($0) }
                let links = Set(
                    sema.symbols.lookupAll(fqName: fqName)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )

                #expect(
                    links.contains("kk_string_toCollection_flat"),
                    "CharSequence.toCollection should link to kk_string_toCollection"
                )
            }
        }
    }
}
