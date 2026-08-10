@testable import CompilerCore
import Testing

/// STDLIB-TEXT-FN-003/004/011/054: Consolidated Sema coverage for
/// `StringBuilder.append`, `StringBuilder.appendLine`, `String.concat`, and
/// `String.repeat`. A single Sema pass resolves all source packages and each
/// `do` block verifies the expected symbol/call bindings.
@Suite
struct StringAppendConcatRepeatFunctionTests {
    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    @Test
    func testAppendConcatRepeatResolveInSource() throws {
        let sources: [String] = [
            """
            package sample0
            import kotlin.text.Appendable

            fun main() {
                val sb = StringBuilder()
                val anyValue: Any? = 42
                val nullableString: String? = null
                sb.append(anyValue)
                sb.append(nullableString)
                sb.append('x')
                sb.append(true)
                sb.append(1)
                sb.append(2L)
                sb.append(3.5f)
                sb.append(4.5)
            }

            fun appendPieces(target: Appendable): Appendable {
                target.append('a')
                target.append("bc")
                return target.append("def", 1, 3)
            }
            """,
            """
            package sample1
            fun main() {
                val sb = StringBuilder()
                sb.appendLine("hello")
                sb.appendLine()

                val result = StringBuilder()
                    .appendLine("first")
                    .appendLine("second")
                    .appendLine()
                    .toString()
                println(result)
            }
            """,
            """
            package sample2
            fun concatTwo(a: String, b: String): String {
                return a.concat(b)
            }

            fun concatLiteral(): String {
                return "Hello".concat(" World")
            }

            fun concatEmpty(s: String): String {
                return s.concat("")
            }

            fun concatChained(a: String, b: String, c: String): String {
                return a.concat(b).concat(c)
            }
            """,
            """
            package sample3
            fun repeatTwice(s: String): String {
                return s.repeat(2)
            }

            fun repeatLiteral(): String {
                return "ab".repeat(3)
            }

            fun repeatZero(s: String): String {
                return s.repeat(0)
            }

            fun repeatWithExpression(s: String, n: Int): String {
                return s.repeat(n + 1)
            }

            fun repeatInConcatenation(s: String): String {
                return "[" + s.repeat(2) + "]"
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let names = ["append", "appendLine", "concat", "repeat"]
            for (index, name) in names.enumerated() {
                let path = paths[index]
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                let errors = pathDiagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected \(name) to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )
            }

            // === append ===
            do {
                let stringBuilderAppendSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("StringBuilder"),
                    interner.intern("append"),
                ])

                let objectLikeTypes = [
                    sema.types.nullableAnyType,
                    sema.types.makeNullable(sema.types.stringType),
                ]
                for parameterType in objectLikeTypes {
                    let overload = stringBuilderAppendSymbols.first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return signature.parameterTypes == [parameterType]
                    }
                    #expect(overload != nil, "Expected StringBuilder.append overload for \(parameterType)")
                    if let overload {
                        #expect(
                            sema.symbols.externalLinkName(for: overload) == nil,
                            "StringBuilder.append overload for \(parameterType) should be source-backed"
                        )
                    }
                }

                let typedParameterTypes = [
                    sema.types.charType,
                    sema.types.booleanType,
                    sema.types.intType,
                    sema.types.longType,
                    sema.types.floatType,
                    sema.types.doubleType,
                ]
                for parameterType in typedParameterTypes {
                    let overload = stringBuilderAppendSymbols.first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return signature.parameterTypes == [parameterType]
                    }
                    #expect(overload != nil, "Expected StringBuilder.append overload for \(parameterType)")
                    if let overload {
                        #expect(
                            sema.symbols.externalLinkName(for: overload) == nil,
                            "StringBuilder.append overload for \(parameterType) should be source-backed"
                        )
                    }
                }

                let appendableAppendSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("Appendable"),
                    interner.intern("append"),
                ])

                #expect(
                    appendableAppendSymbols.contains { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return signature.parameterTypes == [sema.types.charType]
                            && (sema.symbols.externalLinkName(for: symbolID)?.isEmpty ?? true)
                    },
                    "Expected Appendable.append(Char) to have no external link (StringBuilder source overrides)"
                )
                #expect(
                    appendableAppendSymbols.contains { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return signature.parameterTypes.count == 1
                            && sema.symbols.externalLinkName(for: symbolID) == "__kk_string_builder_append_obj"
                    },
                    "Expected Appendable.append(CharSequence?) to link to __kk_string_builder_append_obj"
                )
                #expect(
                    appendableAppendSymbols.contains { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return signature.parameterTypes.count == 3
                            && (sema.symbols.externalLinkName(for: symbolID)?.isEmpty ?? true)
                    },
                    "Expected Appendable.append(CharSequence?, Int, Int) to have no external link (StringBuilder source overrides)"
                )
            }

            // === appendLine ===
            do {
                let sbSymbols = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern("StringBuilder"),
                    interner.intern("appendLine"),
                ])

                let valueOverload = try #require(sbSymbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.parameterTypes.count == 1
                }, "appendLine(value) overload should be registered")
                #expect(
                    sema.symbols.externalLinkName(for: valueOverload) == nil,
                    "appendLine(value) should be source-backed"
                )

                let noArgOverload = try #require(sbSymbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.parameterTypes.isEmpty
                }, "appendLine() no-arg overload should be registered")
                #expect(
                    sema.symbols.externalLinkName(for: noArgOverload) == nil,
                    "appendLine() should be source-backed"
                )
            }

            // === concat ===
            do {
                let path = paths[2]
                let concatCall = try #require(
                    lastExprIDInPath(in: ast, path: path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                        return interner.resolve(callee) == "concat" && args.count == 1
                    },
                    "Expected a member call to concat in sample2"
                )

                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: concatCall)?.chosenCallee,
                    "Expected a call binding for the concat invocation"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_string_concat_flat",
                    "String.concat(str) member call must resolve to kk_string_concat_flat"
                )

                let fq = ["kotlin", "text", "concat"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes == [sema.types.stringType]
                })
                #expect(
                    sema.symbols.externalLinkName(for: symbol) == "kk_string_concat_flat"
                )
                #expect(
                    sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
                    "String.concat(str) should return String"
                )
            }

            // === repeat ===
            do {
                let path = paths[3]
                let repeatCall = try #require(
                    lastExprIDInPath(in: ast, path: path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr else { return false }
                        return interner.resolve(callee) == "repeat" && args.count == 1
                    },
                    "Expected member call to repeat in sample3"
                )

                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: repeatCall)?.chosenCallee,
                    "Expected a call binding for the repeat invocation"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "String.repeat(n) is now a bundled Kotlin function and must not have a C external link"
                )

                let fq = ["kotlin", "text", "repeat"].map { interner.intern($0) }
                let symbol = try #require(sema.symbols.lookupAll(fqName: fq).first { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == sema.types.stringType
                        && signature.parameterTypes == [sema.types.intType]
                })
                #expect(
                    sema.symbols.externalLinkName(for: symbol) == nil,
                    "String.repeat(n) is now a bundled Kotlin function and must not have a C external link"
                )
                #expect(
                    sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.stringType,
                    "String.repeat(n) should return String"
                )
            }
        }
    }
}
