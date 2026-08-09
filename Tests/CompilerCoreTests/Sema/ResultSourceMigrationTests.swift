#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ResultSourceMigrationTests {

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

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
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

    private func memberCallExprIDsInPath(
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

    private func firstUserObjectLiteralDeclIDInPath(
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

    private func findMainBodyStatementsInPath(
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

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testResultAPISymbolsComeFromBundledKotlinSource
            """
            package sample0
            fun noop() {}
            """,
            // testResultCallsResolveToBundledKotlinSourceSymbols
            """
            package sample1

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

            """,
            // testResultBooleanPropertyReadsResolveToBundledKotlinSourceSymbols
            """
            package sample2

                    fun probe(success: Result<Int>, failure: Result<Int>): Boolean {
                        val first = success.isSuccess
                        val second = failure.isFailure
                        return first == second
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testResultAPISymbolsComeFromBundledKotlinSource ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let source = sources[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let errors = sample0Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected bundled Result.kt to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

                let resultFQName = ["kotlin", "Result"].map(interner.intern)
                let resultSymbol = try #require(sema.symbols.lookup(fqName: resultFQName))
                let resultInfo = try #require(sema.symbols.symbol(resultSymbol))
                #expect(resultInfo.kind == .class)
                #expect(!resultInfo.flags.contains(.synthetic), "kotlin.Result should be backed by bundled source")
                #expect(sourcePath(for: resultSymbol, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/Result.kt") == true)

                let runCatchingFQName = ["kotlin", "runCatching"].map(interner.intern)
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

            // === testResultCallsResolveToBundledKotlinSourceSymbols ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let source = sources[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let errors = sample1Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Result source calls to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

                let runCatchingCall = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                    guard case let .call(callee, _, _, _) = expr,
                          let calleeExpr = ast.arena.expr(callee),
                          case let .nameRef(name, _) = calleeExpr
                    else { return false }
                    return interner.resolve(name) == "runCatching"
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
                    let memberCall = try #require(firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == memberName
                    })
                    try expectCallUsesBundledResultSource(
                        memberCall,
                        expectedExternalLink: expectedLink,
                        sema: sema,
                        ctx: ctx
                    )
                }

            }

            // === testResultBooleanPropertyReadsResolveToBundledKotlinSourceSymbols ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let errors = sample2Diagnostics.filter { $0.severity == .error }
                #expect(
                    errors.isEmpty,
                    "Expected Result property reads to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
                )

                for propertyName in ["isSuccess", "isFailure"] {
                    let memberRead = try #require(firstExprIDInPath(in: ast, path: sample2Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == propertyName
                    })
                    let propertySymbol = try #require(sema.bindings.identifierSymbol(for: memberRead))
                    #expect(sema.symbols.externalLinkName(for: propertySymbol) == nil)
                    #expect(sourcePath(for: propertySymbol, sema: sema, ctx: ctx)?.contains("__bundled_kotlin/Result.kt") == true)
                }

            }

        }
    }

}

#endif
