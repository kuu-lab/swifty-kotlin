#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ResultSourceMigrationTests {
    @Test func testResultAPISymbolsComeFromBundledKotlinSource() throws {
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected bundled Result.kt to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let sema = try #require(ctx.sema)
            let resultFQName = ["kotlin", "Result"].map(ctx.interner.intern)
            let resultSymbol = try #require(sema.symbols.lookup(fqName: resultFQName))
            let resultInfo = try #require(sema.symbols.symbol(resultSymbol))
            #expect(resultInfo.kind == .class)
            #expect(!resultInfo.flags.contains(.synthetic), "kotlin.Result should be backed by bundled source")
            #expect(sourcePath(for: resultSymbol, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/Result.kt") == true)

            let runCatchingFQName = ["kotlin", "runCatching"].map(ctx.interner.intern)
            let runCatchingSymbol = try #require(sema.symbols.lookupAll(fqName: runCatchingFQName).first { symbolID in
                sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count == 1
            })
            #expect(sema.symbols.externalLinkName(for: runCatchingSymbol) == "kk_runtime_result_run_catching")
            #expect(sourcePath(for: runCatchingSymbol, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/Result.kt") == true)

            for propertyName in ["isSuccess", "isFailure"] {
                let propertySymbol = try #require(symbol(
                    named: propertyName,
                    under: resultFQName,
                    kind: .property,
                    sema: sema,
                    ctx: ctx
                ))
                #expect(sema.symbols.externalLinkName(for: propertySymbol) == nil)
                #expect(sema.symbols.propertyType(for: propertySymbol) != nil)
            }

            let expectedFunctionLinks: [String: String?] = [
                "getOrNull": nil,
                "getOrDefault": nil,
                "getOrElse": "kk_runtime_result_get_or_else",
                "getOrThrow": nil,
                "exceptionOrNull": nil,
                "map": "kk_runtime_result_map",
                "fold": "kk_runtime_result_fold",
                "onSuccess": "kk_runtime_result_on_success",
                "onFailure": "kk_runtime_result_on_failure",
                "recover": "kk_runtime_result_recover",
                "recoverCatching": "kk_runtime_result_recover_catching",
            ]
            for (functionName, expectedLink) in expectedFunctionLinks {
                let functionSymbol = try #require(symbol(
                    named: functionName,
                    under: resultFQName,
                    kind: .function,
                    sema: sema,
                    ctx: ctx
                ))
                #expect(sema.symbols.externalLinkName(for: functionSymbol) == expectedLink)
                #expect(sema.symbols.functionSignature(for: functionSymbol) != nil)
            }
        }
    }

    @Test func testResultCallsResolveToBundledKotlinSourceSymbols() throws {
        let source = """
        fun failInt(): Int {
            throw RuntimeException("boom")
        }

        fun useResult(): Int {
            val success: Result<Int> = runCatching { 41 }
            val mapped: Result<Any?> = success.map { value -> value }
            val tapped = mapped.onSuccess { value -> println(value) }
            val failure: Result<Int> = runCatching { failInt() }
            val recovered: Result<Any?> = failure.recover { 7 }
            val recoveredCatching: Result<Any?> = failure.recoverCatching { 8 }
            return tapped.getOrDefault(0) + recovered.getOrDefault(0) + recoveredCatching.getOrDefault(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected Result source calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let runCatchingCall = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      let calleeExpr = ast.arena.expr(callee),
                      case let .nameRef(name, _) = calleeExpr
                else { return false }
                return ctx.interner.resolve(name) == "runCatching"
            })
            try expectCallUsesBundledResultSource(
                runCatchingCall,
                expectedExternalLink: "kk_runtime_result_run_catching",
                sema: sema,
                ctx: ctx
            )

            let expectedMemberLinks: [String: String?] = [
                "map": "kk_runtime_result_map",
                "onSuccess": "kk_runtime_result_on_success",
                "recover": "kk_runtime_result_recover",
                "recoverCatching": "kk_runtime_result_recover_catching",
                "getOrDefault": nil,
            ]
            for (memberName, expectedLink) in expectedMemberLinks {
                let memberCall = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == memberName
                })
                try expectCallUsesBundledResultSource(
                    memberCall,
                    expectedExternalLink: expectedLink,
                    sema: sema,
                    ctx: ctx
                )
            }
        }
    }

    @Test func testResultBooleanPropertyReadsResolveToBundledKotlinSourceSymbols() throws {
        let source = """
        fun probe(success: Result<Int>, failure: Result<Int>): Boolean {
            val first = success.isSuccess
            val second = failure.isFailure
            return first == second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected Result property reads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            for propertyName in ["isSuccess", "isFailure"] {
                let memberRead = try #require(firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == propertyName
                })
                let propertySymbol = try #require(sema.bindings.identifierSymbol(for: memberRead))
                #expect(sema.symbols.externalLinkName(for: propertySymbol) == nil)
                #expect(sourcePath(for: propertySymbol, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/Result.kt") == true)
            }
        }
    }

    private func symbol(
        named name: String,
        under ownerFQName: [InternedString],
        kind: SymbolKind,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> SymbolID? {
        let fqName = ownerFQName + [ctx.interner.intern(name)]
        return sema.symbols.lookupAll(fqName: fqName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == kind
        }
    }

    private func sourcePath(
        for symbol: SymbolID,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> String? {
        guard let fileID = sema.symbols.sourceFileID(for: symbol) else { return nil }
        return ctx.sourceManager.path(of: fileID)
    }

    private func expectCallUsesBundledResultSource(
        _ exprID: ExprID,
        expectedExternalLink: String?,
        sema: SemaModule,
        ctx: CompilationContext
    ) throws {
        let chosenCallee = try #require(sema.bindings.callBinding(for: exprID)?.chosenCallee)
        #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedExternalLink)
        #expect(sourcePath(for: chosenCallee, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/Result.kt") == true)
    }
}
#endif
