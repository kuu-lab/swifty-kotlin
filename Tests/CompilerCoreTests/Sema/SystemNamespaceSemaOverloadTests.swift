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
    func testKotlinSystemAPIInventoryMatchesTrackedSurface() throws {
        let (sema, interner) = try makeSema()

        let implementedTopLevelFunctions: [(name: String, link: String)] = [
            ("exitProcess", "kk_system_exitProcess"),
            ("getTimeMicros", "kk_system_getTimeMicros"),
            ("getTimeMillis", "kk_system_getTimeMillis"),
            ("getTimeNanos", "kk_system_getTimeNanos"),
            ("measureTimeMicros", "kk_system_measureTimeMicros"),
            ("measureTimeMillis", "kk_system_measureTimeMillis"),
            ("measureNanoTime", "kk_system_measureNanoTime"),
        ]
        for function in implementedTopLevelFunctions {
            #expect(
                systemPkgExternalLink(for: function.name, sema: sema, interner: interner) == function.link,
                "kotlin.system.\(function.name) should remain implemented via \(function.link)"
            )
        }
        #expect(
            systemPkgStdlibSpecialCallKind(for: "measureTimeMillis", sema: sema, interner: interner) ==
            .measureTimeMillis
        )
        #expect(
            systemPkgStdlibSpecialCallKind(for: "measureTimeMicros", sema: sema, interner: interner) ==
            .measureTimeMicros
        )
        #expect(
            systemPkgStdlibSpecialCallKind(for: "measureNanoTime", sema: sema, interner: interner) ==
            .measureNanoTime
        )

        let systemFQ = ["kotlin", "system", "System"].map { interner.intern($0) }
        let systemSymbol = try #require(
            sema.symbols.lookup(fqName: systemFQ),
            "Existing kotlin.system.System shim should remain registered"
        )
        let systemName = try #require(sema.symbols.symbol(systemSymbol)?.fqName)
        let shimMembers = [
            ("currentTimeMillis", "kk_system_currentTimeMillis"),
            ("nanoTime", "kk_system_nanoTime"),
            ("processStartNanos", "kk_system_process_start_nanos"),
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

    /// measureTimeMillis, measureTimeMicros, and measureNanoTime are distinct top-level symbols
    /// in kotlin.system and map to different runtime entry points.
    @Test
    func testMeasureTimeFunctionsAreRegisteredAsSeparateSymbols() throws {
        let (sema, interner) = try makeSema()

        let millisLink = systemPkgExternalLink(
            for: "measureTimeMillis", sema: sema, interner: interner
        )
        let microsLink = systemPkgExternalLink(
            for: "measureTimeMicros", sema: sema, interner: interner
        )
        let nanoLink = systemPkgExternalLink(
            for: "measureNanoTime", sema: sema, interner: interner
        )

        #expect(
            millisLink == "kk_system_measureTimeMillis",
            "measureTimeMillis must link to kk_system_measureTimeMillis"
        )
        #expect(
            microsLink == "kk_system_measureTimeMicros",
            "measureTimeMicros must link to kk_system_measureTimeMicros"
        )
        #expect(
            nanoLink == "kk_system_measureNanoTime",
            "measureNanoTime must link to kk_system_measureNanoTime"
        )
        #expect(
            millisLink != nanoLink,
            "measureTimeMillis and measureNanoTime must link to distinct runtime functions"
        )
        #expect(
            millisLink != microsLink,
            "measureTimeMillis and measureTimeMicros must link to distinct runtime functions"
        )
        #expect(
            microsLink != nanoLink,
            "measureTimeMicros and measureNanoTime must link to distinct runtime functions"
        )
    }

    @Test
    func testGetTimeMicrosIsRegisteredAsTopLevelNativeFunction() throws {
        let (sema, interner) = try makeSema()
        let link = systemPkgExternalLink(for: "getTimeMicros", sema: sema, interner: interner)
        #expect(link == "kk_system_getTimeMicros")
    }

    @Test
    func testGetTimeMillisIsRegisteredAsTopLevelNativeFunction() throws {
        let (sema, interner) = try makeSema()
        let link = systemPkgExternalLink(for: "getTimeMillis", sema: sema, interner: interner)
        #expect(link == "kk_system_getTimeMillis")
    }

    @Test
    func testGetTimeNanosIsRegisteredAsTopLevelNativeFunction() throws {
        let (sema, interner) = try makeSema()
        let link = systemPkgExternalLink(for: "getTimeNanos", sema: sema, interner: interner)
        #expect(link == "kk_system_getTimeNanos")
    }

    /// exitProcess is a top-level kotlin.system function that accepts an Int parameter.
    @Test
    func testExitProcessIsRegisteredInKotlinSystemPackage() throws {
        let (sema, interner) = try makeSema()

        let link = systemPkgExternalLink(for: "exitProcess", sema: sema, interner: interner)
        #expect(
            link == "kk_system_exitProcess",
            "exitProcess must link to kk_system_exitProcess"
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
            ("currentTimeMillis", "kk_system_currentTimeMillis"),
            ("nanoTime", "kk_system_nanoTime"),
            ("processStartNanos", "kk_system_process_start_nanos"),
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

    /// measureTimeMillis { } call is tagged with .measureTimeMillis special call kind
    /// and resolves to Long.
    ///
    /// Note: measureTimeMillis uses a special fast path in CallTypeChecker that does NOT
    /// set callBinding (KIR lowering drives dispatch directly from the special kind tag).
    /// The test validates the kind tag and return type, matching the compiler's design.
    @Test
    func testMeasureTimeMillisCallResolvesToCorrectCallee() throws {
        let source = """
        import kotlin.system.measureTimeMillis

        fun sample(): Long {
            return measureTimeMillis { }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected no errors for measureTimeMillis call")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "measureTimeMillis"
                },
                "Expected call to measureTimeMillis"
            )

            // Type must be Long
            #expect(
                sema.bindings.exprTypes[callExpr] == sema.types.longType,
                "measureTimeMillis must resolve to Long"
            )

            // Must be tagged as measureTimeMillis special call
            let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
            #expect(kind == .measureTimeMillis, "Expected .measureTimeMillis special call kind")

            // measureTimeMillis fast path does not set callBinding (KIR lowering reads special kind tag).
            // Instead verify the top-level symbol is registered with the correct link name.
            let fq = ["kotlin", "system", "measureTimeMillis"].map { ctx.interner.intern($0) }
            let allSymbols = sema.symbols.lookupAll(fqName: fq)
            let hasLink = allSymbols.contains {
                sema.symbols.externalLinkName(for: $0) == "kk_system_measureTimeMillis"
            }
            #expect(hasLink, "kotlin.system.measureTimeMillis must link to kk_system_measureTimeMillis")
        }
    }

    /// measureTimeMicros { } call is tagged with .measureTimeMicros special call kind
    /// and resolves to Long.
    ///
    /// Note: Like measureTimeMillis, this uses the special fast path that does NOT set callBinding.
    @Test
    func testMeasureTimeMicrosCallResolvesToCorrectCallee() throws {
        let source = """
        import kotlin.system.measureTimeMicros

        fun sample(): Long {
            return measureTimeMicros { }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected no errors for measureTimeMicros call")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "measureTimeMicros"
                },
                "Expected call to measureTimeMicros"
            )

            #expect(
                sema.bindings.exprTypes[callExpr] == sema.types.longType,
                "measureTimeMicros must resolve to Long"
            )

            let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
            #expect(kind == .measureTimeMicros, "Expected .measureTimeMicros special call kind")

            // measureTimeMicros fast path does not set callBinding.
            // Verify the top-level symbol is registered with the correct link name.
            let fq = ["kotlin", "system", "measureTimeMicros"].map { ctx.interner.intern($0) }
            let allSymbols = sema.symbols.lookupAll(fqName: fq)
            let hasLink = allSymbols.contains {
                sema.symbols.externalLinkName(for: $0) == "kk_system_measureTimeMicros"
            }
            #expect(hasLink, "kotlin.system.measureTimeMicros must link to kk_system_measureTimeMicros")
        }
    }

    /// measureNanoTime { } call is tagged with .measureNanoTime special call kind
    /// and resolves to Long.
    ///
    /// Note: Like measureTimeMillis, this uses the special fast path that does NOT set callBinding.
    @Test
    func testMeasureNanoTimeCallResolvesToCorrectCallee() throws {
        let source = """
        import kotlin.system.measureNanoTime

        fun sample(): Long {
            return measureNanoTime { }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected no errors for measureNanoTime call")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return ctx.interner.resolve(calleeName) == "measureNanoTime"
                },
                "Expected call to measureNanoTime"
            )

            // Type must be Long
            #expect(
                sema.bindings.exprTypes[callExpr] == sema.types.longType,
                "measureNanoTime must resolve to Long"
            )

            // Must be tagged as measureNanoTime special call
            let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
            #expect(kind == .measureNanoTime, "Expected .measureNanoTime special call kind")

            // measureNanoTime fast path does not set callBinding.
            // Verify the top-level symbol is registered with the correct link name.
            let fq = ["kotlin", "system", "measureNanoTime"].map { ctx.interner.intern($0) }
            let allSymbols = sema.symbols.lookupAll(fqName: fq)
            let hasLink = allSymbols.contains {
                sema.symbols.externalLinkName(for: $0) == "kk_system_measureNanoTime"
            }
            #expect(hasLink, "kotlin.system.measureNanoTime must link to kk_system_measureNanoTime")
        }
    }

    /// measureTimeMillis, measureTimeMicros, and measureNanoTime must produce distinct special call kind tags
    /// when used in the same translation unit (overload disambiguation).
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

            var millisKind: StdlibSpecialCallKind?
            var microsKind: StdlibSpecialCallKind?
            var nanoKind: StdlibSpecialCallKind?

            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { continue }

                let name = ctx.interner.resolve(calleeName)
                let kind = sema.bindings.stdlibSpecialCallKind(for: exprID)

                if name == "measureTimeMillis" { millisKind = kind }
                if name == "measureTimeMicros" { microsKind = kind }
                if name == "measureNanoTime" { nanoKind = kind }
            }

            #expect(millisKind == .measureTimeMillis, "measureTimeMillis must be tagged .measureTimeMillis")
            #expect(microsKind == .measureTimeMicros, "measureTimeMicros must be tagged .measureTimeMicros")
            #expect(nanoKind == .measureNanoTime, "measureNanoTime must be tagged .measureNanoTime")
            #expect(
                millisKind != nanoKind,
                "measureTimeMillis and measureNanoTime must have distinct special call kind tags"
            )
            #expect(
                millisKind != microsKind,
                "measureTimeMillis and measureTimeMicros must have distinct special call kind tags"
            )
            #expect(
                microsKind != nanoKind,
                "measureTimeMicros and measureNanoTime must have distinct special call kind tags"
            )
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
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == "kk_system_exitProcess"
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
