#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ContextHelperSyntheticStubTests {

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [fakePath])
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }

    private func lookupSymbol(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) })
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    private func typeParamType(_ symbol: SymbolID, sema: SemaModule) -> TypeID {
        sema.types.make(.typeParam(TypeParamType(symbol: symbol, nullability: .nonNull)))
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
            // testContextHelperIsRegisteredWithContextFunctionBlock
            """
            package sample0
            fun noop() {}
            """,
            // testContextHelperRegistersOverloadsThroughAritySix
            """
            package sample1
            fun noop() {}
            """,
            // testContextOfHelperIsRegistered
            """
            package sample2
            fun noop() {}
            """,
            // testContextHelperAcceptsOptInAndInfersBlockReturnType
            """
            package sample3

                    import kotlin.ExperimentalContextParameters

                    @OptIn(ExperimentalContextParameters::class)
                    fun caller(): String = context(1) { "ok" }

            """,
            // testContextOfResolvesInsideContextHelperBlock
            """
            package sample4

                    import kotlin.ExperimentalContextParameters

                    @OptIn(ExperimentalContextParameters::class)
                    fun caller(): String = context("ok") { contextOf<String>() }

            """,
            // testContextHelperSixValueOverloadInfersBlockReturnType
            """
            package sample5

                    import kotlin.ExperimentalContextParameters

                    @OptIn(ExperimentalContextParameters::class)
                    fun caller(): String = context(1, 2, 3, 4, 5, 6) { "ok" }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testContextHelperIsRegisteredWithContextFunctionBlock ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let contextSymbol = try #require(lookupSymbol(["kotlin", "context"], sema: sema, interner: interner))
                let symbol = try #require(sema.symbols.symbol(contextSymbol))
                let signature = try #require(sema.symbols.functionSignature(for: contextSymbol))

                #expect(symbol.flags.contains(.synthetic))
                #expect(symbol.flags.contains(.inlineFunction))
                #expect(signature.parameterTypes.count == 2)
                #expect(signature.typeParameterSymbols.count == 2)
                #expect(signature.returnType == typeParamType(signature.typeParameterSymbols[1], sema: sema))

                let contextType = typeParamType(signature.typeParameterSymbols[0], sema: sema)
                #expect(signature.parameterTypes[0] == contextType)
                guard case let .functionType(blockType) = sema.types.kind(of: signature.parameterTypes[1]) else {
                    Issue.record("context block parameter should be a function type")
                    return
                }
                #expect(blockType.contextReceivers == [contextType])
                #expect(blockType.params.isEmpty)
                #expect(blockType.returnType == signature.returnType)

            }

            // === testContextHelperRegistersOverloadsThroughAritySix ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let contextSymbols = sema.symbols.lookupAll(fqName: ["kotlin", "context"].map { interner.intern($0) })
                let arities = Set(contextSymbols.compactMap { symbolID -> Int? in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          case let .functionType(blockType) = sema.types.kind(of: signature.parameterTypes.last ?? .invalid),
                          blockType.params.isEmpty
                    else {
                        return nil
                    }
                    return blockType.contextReceivers.count
                })

                #expect(arities == Set(1...6))

            }

            // === testContextOfHelperIsRegistered ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let contextOfSymbol = try #require(lookupSymbol(["kotlin", "contextOf"], sema: sema, interner: interner))
                let symbol = try #require(sema.symbols.symbol(contextOfSymbol))
                let signature = try #require(sema.symbols.functionSignature(for: contextOfSymbol))

                #expect(symbol.flags.contains(.synthetic))
                #expect(symbol.flags.contains(.inlineFunction))
                #expect(signature.parameterTypes == [])
                #expect(signature.typeParameterSymbols.count == 1)
                #expect(signature.returnType == typeParamType(signature.typeParameterSymbols[0], sema: sema))
                #expect(sema.symbols.annotations(for: contextOfSymbol).contains { annotation in
                    annotation.annotationFQName == "kotlin.ExperimentalContextParameters"
                })

            }

            // === testContextHelperAcceptsOptInAndInfersBlockReturnType ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(diagnosticsForPath(sample3Path, withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty, "Expected @OptIn to suppress context helper diagnostic, got: \(sample3Diagnostics)")
                let callerSymbol = try #require(lookupSymbol(["sample3", "caller"], sema: sema, interner: interner))
                let signature = try #require(sema.symbols.functionSignature(for: callerSymbol))
                #expect(signature.returnType == sema.types.stringType)

            }

            // === testContextOfResolvesInsideContextHelperBlock ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(diagnosticsForPath(sample4Path, withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty, "Expected @OptIn to suppress contextOf diagnostic, got: \(sample4Diagnostics)")
                #expect(diagnosticsForPath(sample4Path, withCode: "KSWIFTK-SEMA-CTX-001", in: ctx).isEmpty, "Expected contextOf<String>() to find the String context receiver, got: \(sample4Diagnostics)")
                let callerSymbol = try #require(lookupSymbol(["sample4", "caller"], sema: sema, interner: interner))
                let signature = try #require(sema.symbols.functionSignature(for: callerSymbol))
                #expect(signature.returnType == sema.types.stringType)

            }

            // === testContextHelperSixValueOverloadInfersBlockReturnType ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                #expect(diagnosticsForPath(sample5Path, withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx).isEmpty, "Expected @OptIn to suppress context helper diagnostic, got: \(sample5Diagnostics)")
                let callerSymbol = try #require(lookupSymbol(["sample5", "caller"], sema: sema, interner: interner))
                let signature = try #require(sema.symbols.functionSignature(for: callerSymbol))
                #expect(signature.returnType == sema.types.stringType)

            }

        }
    }

    // MARK: - Consolidated runSema error tests

    @Test
    func testRunSemaWithExpectedDiagnostics() throws {

        let sources: [String] = [
            // testContextHelperRequiresExperimentalContextParametersOptIn
            """
            package sample0

                    fun caller(): Int = context(1) { 2 }

            """,
            // testContextOfReportsMissingContextReceiver
            """
            package sample1

                    import kotlin.ExperimentalContextParameters

                    @OptIn(ExperimentalContextParameters::class)
                    fun caller(): Int = context("ok") { contextOf<Int>() }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testContextHelperRequiresExperimentalContextParametersOptIn ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let diagnostics = diagnosticsForPath(sample0Path, withCode: "KSWIFTK-SEMA-OPT-IN", in: ctx)

                #expect(diagnostics.count == 1, "Expected context helper to require opt-in, got: \(sample0Diagnostics)")
                #expect(diagnostics.first?.message.contains("ExperimentalContextParameters") == true)

            }

            // === testContextOfReportsMissingContextReceiver ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diagnostics = diagnosticsForPath(sample1Path, withCode: "KSWIFTK-SEMA-CTX-001", in: ctx)
                #expect(diagnostics.count == 1, "Expected missing context receiver diagnostic, got: \(sample1Diagnostics)")

            }

        }
    }

}

#endif
