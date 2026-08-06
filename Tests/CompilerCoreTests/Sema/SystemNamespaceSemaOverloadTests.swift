@testable import CompilerCore
import Foundation
import Testing

/// Sema-level coverage for the kotlin.system namespace (STDLIB-SYSTEM-001/002).
///
/// Tests cover:
/// - measureTimeMillis / measureTimeMicros / measureNanoTime overload disambiguation
/// - exitProcess(Int) signature resolution and Nothing return type
/// - getTimeMicros top-level Native API visibility
/// - getTimeMillis top-level Native API visibility
/// - getTimeNanos top-level Native API visibility
/// - System.currentTimeMillis / System.nanoTime member visibility
/// - getTimeMillis (alias currentTimeMillis) and getTimeNanos (alias nanoTime) via System object
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

    private func systemPkgIsDeclared(
        _ name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let fq = ["kotlin", "system", name].map { interner.intern($0) }
        return !sema.symbols.lookupAll(fqName: fq).isEmpty
    }

    /// All runtime link names registered anywhere in the module, used to assert
    /// that the bundled `__kk_system_*` bridges exist (KSP-617).
    private func allExternalLinks(sema: SemaModule) -> Set<String> {
        Set(sema.symbols.allSymbols().compactMap { sema.symbols.externalLinkName(for: $0.id) })
    }

    // MARK: - STDLIB-SYSTEM-001: API list / symbol registration

    @Test
    func testKotlinSystemAPIInventoryMatchesTrackedSurface() throws {
        let (sema, interner) = try makeSema()

        // KSP-617: the public surface lives in bundled Kotlin source; the OS
        // entry points are private `__kk_system_*` bridges.
        let publicTopLevelFunctions = [
            "exitProcess",
            "getTimeMicros",
            "getTimeMillis",
            "getTimeNanos",
            "measureTimeMicros",
            "measureTimeMillis",
            "measureNanoTime",
        ]
        for name in publicTopLevelFunctions {
            #expect(
                systemPkgIsDeclared(name, sema: sema, interner: interner),
                "kotlin.system.\(name) should be declared in bundled Kotlin source"
            )
            #expect(
                systemPkgExternalLink(for: name, sema: sema, interner: interner) == nil,
                "kotlin.system.\(name) must not be an external runtime declaration"
            )
        }

        let links = allExternalLinks(sema: sema)
        for bridge in [
            "__kk_system_exitProcess",
            "__kk_system_getTimeMicros",
            "__kk_system_getTimeMillis",
            "__kk_system_getTimeNanos",
        ] {
            #expect(links.contains(bridge), "\(bridge) bridge must be declared")
        }

        let systemFQ = ["kotlin", "system", "System"].map { interner.intern($0) }
        let systemSymbol = try #require(
            sema.symbols.lookup(fqName: systemFQ),
            "Existing kotlin.system.System shim should remain registered"
        )
        let systemName = try #require(sema.symbols.symbol(systemSymbol)?.fqName)
        let shimMembers = [
            ("currentTimeMillis", "__kk_system_currentTimeMillis"),
            ("nanoTime", "__kk_system_nanoTime"),
            ("processStartNanos", "__kk_system_process_start_nanos"),
        ]
        for member in shimMembers {
            let memberFQ = systemName + [interner.intern(member.0)]
            #expect(
                sema.symbols.lookupAll(fqName: memberFQ).contains {
                    sema.symbols.externalLinkName(for: $0) == member.1
                },
                "kotlin.system.System.\(member.0) should remain linked to \(member.1)"
            )
        }
    }

    /// measureTimeMillis, measureTimeMicros, and measureNanoTime are distinct
    /// top-level Kotlin symbols in kotlin.system, each backed by its own clock
    /// bridge.
    @Test
    func testMeasureTimeFunctionsAreRegisteredAsSeparateSymbols() throws {
        let (sema, interner) = try makeSema()

        for name in ["measureTimeMillis", "measureTimeMicros", "measureNanoTime"] {
            #expect(
                systemPkgIsDeclared(name, sema: sema, interner: interner),
                "kotlin.system.\(name) must be declared"
            )
        }

        let links = allExternalLinks(sema: sema)
        for bridge in [
            "__kk_system_getTimeMillis", "__kk_system_getTimeMicros", "__kk_system_getTimeNanos",
        ] {
            #expect(links.contains(bridge), "\(bridge) must back the measureTime* implementations")
        }
    }

    @Test
    func testGetTimeMicrosIsRegisteredAsTopLevelNativeFunction() throws {
        let (sema, interner) = try makeSema()
        #expect(systemPkgIsDeclared("getTimeMicros", sema: sema, interner: interner))
        #expect(allExternalLinks(sema: sema).contains("__kk_system_getTimeMicros"))
    }

    @Test
    func testGetTimeMillisIsRegisteredAsTopLevelNativeFunction() throws {
        let (sema, interner) = try makeSema()
        #expect(systemPkgIsDeclared("getTimeMillis", sema: sema, interner: interner))
        #expect(allExternalLinks(sema: sema).contains("__kk_system_getTimeMillis"))
    }

    @Test
    func testGetTimeNanosIsRegisteredAsTopLevelNativeFunction() throws {
        let (sema, interner) = try makeSema()
        #expect(systemPkgIsDeclared("getTimeNanos", sema: sema, interner: interner))
        #expect(allExternalLinks(sema: sema).contains("__kk_system_getTimeNanos"))
    }

    /// exitProcess is a top-level kotlin.system function that accepts an Int parameter.
    @Test
    func testExitProcessIsRegisteredInKotlinSystemPackage() throws {
        let (sema, interner) = try makeSema()

        #expect(
            systemPkgIsDeclared("exitProcess", sema: sema, interner: interner),
            "exitProcess must be declared in bundled Kotlin source"
        )
        #expect(
            allExternalLinks(sema: sema).contains("__kk_system_exitProcess"),
            "exitProcess must be backed by the __kk_system_exitProcess bridge"
        )
    }

    /// The System object members (currentTimeMillis, nanoTime, processStartNanos)
    /// must be registered and link to the correct runtime functions.
    @Test
    func testSystemObjectMembersAreRegistered() throws {
        let (sema, interner) = try makeSema()

        // Look up the System object symbol under kotlin.system
        let systemFQ = ["kotlin", "system", "System"].map { interner.intern($0) }
        let systemSymbolID = sema.symbols.lookup(fqName: systemFQ)
        #expect(systemSymbolID != nil, "kotlin.system.System object must be registered")

        guard let ownerID = systemSymbolID else { return }
        let ownerSymbol = try #require(sema.symbols.symbol(ownerID))

        // Verify expected member links on the System object
        let expectedMembers: [(String, String)] = [
            ("currentTimeMillis", "__kk_system_currentTimeMillis"),
            ("nanoTime", "__kk_system_nanoTime"),
            ("processStartNanos", "__kk_system_process_start_nanos"),
        ]

        for (memberName, expectedLink) in expectedMembers {
            let memberFQ = ownerSymbol.fqName + [interner.intern(memberName)]
            let memberSymbols = sema.symbols.lookupAll(fqName: memberFQ)
            let foundLink = memberSymbols.contains { id in
                sema.symbols.externalLinkName(for: id) == expectedLink
            }
            #expect(
                foundLink,
                "System.\(memberName) must link to \(expectedLink)"
            )
        }
    }

    // MARK: - STDLIB-SYSTEM-002: Sema overload resolution

    /// KSP-617: measureTime* are ordinary bundled Kotlin functions — they
    /// resolve through normal overload resolution to Long, without a
    /// StdlibSpecialCallKind tag.
    @Test
    func testMeasureTimeFunctionsResolveToBundledKotlinDeclarations() throws {
        for name in ["measureTimeMillis", "measureTimeMicros", "measureNanoTime"] {
            let source = """
            import kotlin.system.\(name)

            fun sample(): Long {
                return \(name) { }
            }
            """

            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)

                #expect(!(ctx.diagnostics.hasError), "Expected no errors for \(name) call")

                let ast = try #require(ctx.ast)
                let sema = try #require(ctx.sema)

                let callExpr = try #require(
                    firstExprID(in: ast) { _, expr in
                        guard case let .call(calleeExpr, _, _, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return ctx.interner.resolve(calleeName) == name
                    },
                    "Expected call to \(name)"
                )

                #expect(
                    sema.bindings.exprTypes[callExpr] == sema.types.longType,
                    "\(name) must resolve to Long"
                )
                #expect(
                    sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil,
                    "\(name) must no longer be a stdlib special call"
                )

                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected a chosen callee for \(name)"
                )
                let fqName = try #require(sema.symbols.symbol(chosenCallee)?.fqName)
                    .map { ctx.interner.resolve($0) }
                #expect(fqName == ["kotlin", "system", name], "Unexpected callee: \(fqName)")
            }
        }
    }

    /// measureTimeMillis, measureTimeMicros, and measureNanoTime must resolve to
    /// distinct callees when used in the same translation unit.
    @Test
    func testMeasureTimeFunctionsResolveToDistinctCallees() throws {
        let source = """
        import kotlin.system.*

        fun sample(): Long {
            val a = measureTimeMillis { }
            val b = measureTimeMicros { }
            val c = measureNanoTime { }
            return a + b + c
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected no errors")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            var callees: [String: SymbolID] = [:]
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr),
                      let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee
                else { continue }
                callees[ctx.interner.resolve(calleeName)] = chosen
            }

            let millis = try #require(callees["measureTimeMillis"])
            let micros = try #require(callees["measureTimeMicros"])
            let nanos = try #require(callees["measureNanoTime"])
            #expect(Set([millis, micros, nanos]).count == 3, "measureTime* must resolve to distinct callees")
        }
    }

    /// exitProcess(Int) resolves with a single Int parameter and Nothing return type.
    @Test
    func testExitProcessSignatureResolution() throws {
        let source = """
        import kotlin.system.exitProcess

        fun sample() {
            exitProcess(0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected no errors for exitProcess call")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "exitProcess"
                },
                "Expected call to exitProcess"
            )

            // Return type should be Nothing
            #expect(
                sema.bindings.exprTypes[callExpr] == sema.types.nothingType,
                "exitProcess must have Nothing return type"
            )

            // Chosen callee must link to the exitProcess runtime function
            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected a chosen callee for exitProcess"
            )
            let calleeFQName = try #require(sema.symbols.symbol(chosenCallee)?.fqName)
                .map { ctx.interner.resolve($0) }
            #expect(calleeFQName == ["kotlin", "system", "exitProcess"])
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

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.hasError,
                "exitProcess() without arguments must produce a sema error"
            )
        }
    }

    // MARK: - STDLIB-SYSTEM-001: getTimeMillis / getTimeNanos visibility per platform

    /// System.currentTimeMillis() (analogous to getTimeMillis) is visible as a
    /// member of the kotlin.system.System object.
    @Test
    func testSystemCurrentTimeMillisIsVisible() throws {
        let source = """
        import kotlin.system.System

        fun sample(): Long {
            return System.currentTimeMillis()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !(ctx.diagnostics.hasError),
                "System.currentTimeMillis() must be resolvable without errors; got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let memberCallExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "currentTimeMillis"
                },
                "Expected member call to currentTimeMillis"
            )

            #expect(
                sema.bindings.exprTypes[memberCallExpr] == sema.types.longType,
                "System.currentTimeMillis() must return Long"
            )
        }
    }

    /// System.nanoTime() (analogous to getTimeNanos) is visible as a
    /// member of the kotlin.system.System object.
    @Test
    func testSystemNanoTimeIsVisible() throws {
        let source = """
        import kotlin.system.System

        fun sample(): Long {
            return System.nanoTime()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !(ctx.diagnostics.hasError),
                "System.nanoTime() must be resolvable without errors; got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let memberCallExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "nanoTime"
                },
                "Expected member call to nanoTime"
            )

            #expect(
                sema.bindings.exprTypes[memberCallExpr] == sema.types.longType,
                "System.nanoTime() must return Long"
            )
        }
    }

    /// Both System.currentTimeMillis() and System.nanoTime() must resolve in the
    /// same translation unit, and their return types must both be Long.
    @Test
    func testCurrentTimeMillisAndNanoTimeBothVisibleInSameFile() throws {
        let source = """
        import kotlin.system.System

        fun sample(): Long {
            val ms = System.currentTimeMillis()
            val ns = System.nanoTime()
            return ms + ns
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                !(ctx.diagnostics.hasError),
                "Both System time members must be visible without errors"
            )
        }
    }
}
