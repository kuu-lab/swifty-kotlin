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

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

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

    @Test
    func testKotlinSystemSymbolsAreRegistered() throws {
        let (sema, interner) = try makeSema()

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

    // MARK: - STDLIB-SYSTEM-002: Sema overload resolution

    /// Verifies that calls to kotlin.system top-level functions and System object members
    /// resolve to the expected types, special call kinds, and runtime links in a single
    /// Sema pass.
    @Test
    func testKotlinSystemCallExpressionsResolve() throws {
        let source = """
        import kotlin.system.*

        fun measureMillisSample(): Long = measureTimeMillis { }
        fun measureMicrosSample(): Long = measureTimeMicros { }
        fun measureNanosSample(): Long = measureNanoTime { }
        fun exitProcessSample() { exitProcess(0) }
        fun currentTimeMillisSample(): Long = System.currentTimeMillis()
        fun nanoTimeSample(): Long = System.nanoTime()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(
            !ctx.diagnostics.hasError,
            "Expected kotlin.system call expressions to resolve cleanly, got: \(diagnosticSummary)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        // Table of top-level calls: (name, expectedSpecialKind, expectedReturnType, expectedLink)
        let topLevelCalls: [(String, StdlibSpecialCallKind?, TypeID, String)] = [
            ("measureTimeMillis", .measureTimeMillis, sema.types.longType, "kk_system_measureTimeMillis"),
            ("measureTimeMicros", .measureTimeMicros, sema.types.longType, "kk_system_measureTimeMicros"),
            ("measureNanoTime", .measureNanoTime, sema.types.longType, "kk_system_measureNanoTime"),
            ("exitProcess", nil, sema.types.nothingType, "kk_system_exitProcess"),
        ]

        for (name, expectedKind, expectedReturnType, expectedLink) in topLevelCalls {
            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
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
                firstExprID(in: ast) { _, expr in
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

    /// exitProcess must reject a call without an Int argument (wrong arity).
    @Test
    func testExitProcessWithWrongArityProducesDiagnostic() throws {
        let source = """
        import kotlin.system.exitProcess

        fun sample() {
            exitProcess()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.hasError,
            "exitProcess() without arguments must produce a sema error"
        )
    }
}
