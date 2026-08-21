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

    // KSP-613: `runCatching` no longer has a compiler name special case, so
    // every call shape has to go through ordinary overload resolution against
    // the bundled `kotlin.runCatching` declaration.
    @Test func testRunCatchingCallShapesResolveThroughOrdinaryResolution() throws {
        let source = """
        fun answer(): Int = 42

        fun useRunCatching(): Int {
            val block: Result<Int> = runCatching { answer() }
            val callableRef: Result<Int> = runCatching(::answer)
            val explicit: Result<String> = runCatching<String> { "explicit" }
            val nested: Result<Result<Int>> = runCatching { runCatching { 7 } }
            return block.getOrDefault(0) + callableRef.getOrDefault(0) +
                explicit.getOrDefault("").length + nested.getOrNull()?.getOrDefault(0)!!
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(
                errors.isEmpty,
                "Expected every runCatching call shape to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let sourceFileID = try #require(ctx.sourceManager.fileID(forPath: path))

            // Re-inferred lambda bodies leave duplicate call exprs in the
            // arena, so group by source range and require one bound callee
            // per written call site. Bundled stdlib implementations are in
            // the same AST, so restrict this inventory to the test source.
            var runCatchingCallSites: [SourceRange: [ExprID]] = [:]
            for index in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(index))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(callee, _, _, range) = expr,
                      range.start.file == sourceFileID,
                      let calleeExpr = ast.arena.expr(callee),
                      case let .nameRef(name, _) = calleeExpr,
                      ctx.interner.resolve(name) == "runCatching"
                else { continue }
                runCatchingCallSites[range, default: []].append(exprID)
            }
            #expect(runCatchingCallSites.count == 5)
            for (range, exprIDs) in runCatchingCallSites {
                let boundCall = exprIDs.first { sema.bindings.callBinding(for: $0) != nil }
                let call = try #require(
                    boundCall,
                    "runCatching call at offset \(range.start.offset) must resolve through ordinary call resolution"
                )
                try expectCallUsesBundledResultSource(
                    call,
                    expectedExternalLink: "kk_runtime_result_run_catching",
                    sema: sema,
                    ctx: ctx
                )
            }
        }
    }

    // KSP-613: `Result.fold` passes both callbacks as (fnPtr, closureRaw)
    // pairs. Expanding them before parameter-mapping normalization dropped the
    // onFailure pair, so the runtime received a null onFailure function
    // pointer and crashed as soon as the folded Result was a failure.
    @Test func testResultFoldLowersBothCallbackPairs() throws {
        let source = """
        fun boom(): Int = throw IllegalStateException("boom")

        fun foldFailure(): String {
            return runCatching { boom() }.fold({ value -> "v" + value }, { error -> "e" + error.message })
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try #require(ctx.kir)

            let foldCallArguments = try #require(findAllKIRFunctions(in: module)
                .flatMap(\.body)
                .compactMap { instruction -> [KIRExprID]? in
                    guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                          ctx.interner.resolve(callee) == "kk_runtime_result_fold"
                    else { return nil }
                    return arguments
                }
                .first)

            // (resultRaw, successFnPtr, successClosureRaw, failureFnPtr, failureClosureRaw)
            #expect(foldCallArguments.count == 5)
            for (label, index) in [("onSuccess", 1), ("onFailure", 3)] {
                let callbackKind = module.arena.expr(foldCallArguments[index])
                guard case .symbolRef = callbackKind else {
                    Issue.record("\(label) callback must be lowered to a function pointer, got \(String(describing: callbackKind))")
                    continue
                }
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
