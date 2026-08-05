@testable import CompilerCore
import Foundation
import Testing

/// Sema-level coverage for the kotlin.system namespace (STDLIB-SYSTEM-001/002).
///
/// The suite runs a small number of consolidated Sema pipelines and verifies
/// symbol registration and call resolution in tabular form. This reduces the
/// per-API pipeline initializations that used to happen for every individual test.
@Suite
struct SystemNamespaceSemaOverloadTests {

    // MARK: - Helpers
    private func systemPkgExternalLink(
        for name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "system", name].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func systemPkgStdlibSpecialCallKind(
        for name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> StdlibSpecialCallKind? {
        let fq = ["kotlin", "system", name].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.stdlibSpecialCallKind(forSymbol: sym)
    }

    // MARK: - STDLIB-SYSTEM-001: API list / symbol registration

    // MARK: - STDLIB-SYSTEM-002: Sema overload resolution

    /// Verifies that calls to kotlin.system top-level functions and System object members
    /// resolve to the expected types, special call kinds, and runtime links in a single
    /// Sema pass.

    /// exitProcess must reject a call without an Int argument (wrong arity).

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
            // testKotlinSystemSymbolsAreRegistered
            """
            package sample0
            fun noop() {}
            """,
            // testKotlinSystemCallExpressionsResolve
            """
            package sample1

                    import kotlin.system.*

                    fun measureMillisSample(): Long = measureTimeMillis { }
                    fun measureMicrosSample(): Long = measureTimeMicros { }
                    fun measureNanosSample(): Long = measureNanoTime { }
                    fun exitProcessSample() { exitProcess(0) }
                    fun currentTimeMillisSample(): Long = System.currentTimeMillis()
                    fun nanoTimeSample(): Long = System.nanoTime()

            """,
            // testExitProcessWithWrongArityProducesDiagnostic
            """
            package sample2

                    import kotlin.system.exitProcess

                    fun sample() {
                        exitProcess()
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testKotlinSystemSymbolsAreRegistered ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let expectedTopLevelFunctions: [(name: String, link: String)] = [
                    ("exitProcess", "kk_system_exitProcess"),
                    ("getTimeMicros", "kk_system_getTimeMicros"),
                    ("getTimeMillis", "kk_system_getTimeMillis"),
                    ("getTimeNanos", "kk_system_getTimeNanos"),
                    ("measureTimeMicros", "kk_system_measureTimeMicros"),
                    ("measureTimeMillis", "kk_system_measureTimeMillis"),
                    ("measureNanoTime", "kk_system_measureNanoTime"),
                ]
                for function in expectedTopLevelFunctions {
                    #expect(
                        systemPkgExternalLink(for: function.name, sema: sema, interner: interner) == function.link,
                        "kotlin.system.\(function.name) should remain implemented via \(function.link)"
                    )
                }

                let expectedSpecialKinds: [(String, StdlibSpecialCallKind)] = [
                    ("measureTimeMillis", .measureTimeMillis),
                    ("measureTimeMicros", .measureTimeMicros),
                    ("measureNanoTime", .measureNanoTime),
                ]
                for (name, kind) in expectedSpecialKinds {
                    #expect(
                        systemPkgStdlibSpecialCallKind(for: name, sema: sema, interner: interner) == kind,
                        "kotlin.system.\(name) should have special call kind .\(kind)"
                    )
                }

                #expect(
                    systemPkgExternalLink(for: "measureTimeMillis", sema: sema, interner: interner) !=
                    systemPkgExternalLink(for: "measureTimeMicros", sema: sema, interner: interner),
                    "measureTimeMillis and measureTimeMicros must link to distinct runtime functions"
                )
                #expect(
                    systemPkgExternalLink(for: "measureTimeMillis", sema: sema, interner: interner) !=
                    systemPkgExternalLink(for: "measureNanoTime", sema: sema, interner: interner),
                    "measureTimeMillis and measureNanoTime must link to distinct runtime functions"
                )
                #expect(
                    systemPkgExternalLink(for: "measureTimeMicros", sema: sema, interner: interner) !=
                    systemPkgExternalLink(for: "measureNanoTime", sema: sema, interner: interner),
                    "measureTimeMicros and measureNanoTime must link to distinct runtime functions"
                )

                let systemFQ = ["kotlin", "system", "System"].map { interner.intern($0) }
                let systemSymbol = try #require(
                    sema.symbols.lookup(fqName: systemFQ),
                    "kotlin.system.System object must be registered"
                )
                let systemName = try #require(sema.symbols.symbol(systemSymbol)?.fqName)
                let expectedSystemMembers: [(String, String)] = [
                    ("currentTimeMillis", "kk_system_currentTimeMillis"),
                    ("nanoTime", "kk_system_nanoTime"),
                    ("processStartNanos", "kk_system_process_start_nanos"),
                ]
                for (member, link) in expectedSystemMembers {
                    let memberFQ = systemName + [interner.intern(member)]
                    #expect(
                        sema.symbols.lookupAll(fqName: memberFQ).contains {
                            sema.symbols.externalLinkName(for: $0) == link
                        },
                        "kotlin.system.System.\(member) should remain linked to \(link)"
                    )
                }

            }

            // === testKotlinSystemCallExpressionsResolve ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let diagnosticSummary = sample1Diagnostics
                    .map { "\($0.code): \($0.message)" }
                    .joined(separator: " | ")
                #expect(
                    !sample1Diagnostics.contains { $0.severity == .error },
                    "Expected kotlin.system call expressions to resolve cleanly, got: \(diagnosticSummary)"
                )

                // Table of top-level calls: (name, expectedSpecialKind, expectedReturnType, expectedLink)
                let topLevelCalls: [(String, StdlibSpecialCallKind?, TypeID, String)] = [
                    ("measureTimeMillis", .measureTimeMillis, sema.types.longType, "kk_system_measureTimeMillis"),
                    ("measureTimeMicros", .measureTimeMicros, sema.types.longType, "kk_system_measureTimeMicros"),
                    ("measureNanoTime", .measureNanoTime, sema.types.longType, "kk_system_measureNanoTime"),
                    ("exitProcess", nil, sema.types.nothingType, "kk_system_exitProcess"),
                ]

                for (name, expectedKind, expectedReturnType, expectedLink) in topLevelCalls {
                    let callExpr = try #require(
                        firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                            guard case let .call(calleeExpr, _, _, _) = expr,
                                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                            else {
                                return false
                            }
                            return interner.resolve(calleeName) == name
                        },
                        "Expected call to \(name)"
                    )

                    #expect(
                        sema.bindings.exprTypes[callExpr] == expectedReturnType,
                        "\(name) must return \(expectedReturnType)"
                    )

                    if let expectedKind {
                        let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                        #expect(
                            kind == expectedKind,
                            "\(name) must be tagged .\(expectedKind), got \(String(describing: kind))"
                        )
                    }

                    if name == "exitProcess" {
                        let chosenCallee = try #require(
                            sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                            "Expected a chosen callee for \(name)"
                        )
                        #expect(
                            sema.symbols.externalLinkName(for: chosenCallee) == expectedLink,
                            "\(name) must link to \(expectedLink)"
                        )
                    } else {
                        // measureTime* uses a special fast path that does not set callBinding.
                        // Verify the top-level symbol is registered with the correct link name.
                        let fq = ["kotlin", "system", name].map { interner.intern($0) }
                        let allSymbols = sema.symbols.lookupAll(fqName: fq)
                        #expect(
                            allSymbols.contains { sema.symbols.externalLinkName(for: $0) == expectedLink },
                            "kotlin.system.\(name) must link to \(expectedLink)"
                        )
                    }
                }

                // Table of System object member calls: (name, expectedReturnType)
                let systemMemberCalls: [(String, TypeID)] = [
                    ("currentTimeMillis", sema.types.longType),
                    ("nanoTime", sema.types.longType),
                ]

                for (name, expectedReturnType) in systemMemberCalls {
                    let memberCallExpr = try #require(
                        firstExprIDInPath(in: ast, path: sample1Path, ctx: ctx) { _, expr in
                            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                            return interner.resolve(callee) == name
                        },
                        "Expected member call to System.\(name)"
                    )

                    #expect(
                        sema.bindings.exprTypes[memberCallExpr] == expectedReturnType,
                        "System.\(name) must return \(expectedReturnType)"
                    )
                }

            }

            // === testExitProcessWithWrongArityProducesDiagnostic ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(
                    sample2Diagnostics.contains { $0.severity == .error },
                    "exitProcess() without arguments must produce a sema error"
                )

            }

        }
    }

}
