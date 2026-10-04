#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1480: keep Clock.Companion and Clock.System as distinct public nominal objects.
@Suite
struct ClockSyntheticSurfaceTests {
    private static let source = """
    import kotlin.time.Clock
    import kotlin.time.Instant

    fun companionIdentity(): Clock.Companion = Clock.Companion
    fun localCompanion(): Clock.Companion {
        val companion: Clock.Companion = Clock.Companion
        return companion
    }
    fun systemAsClock(): Clock = Clock.System
    fun systemNow(): Instant = Clock.System.now()

    class CustomClock : Clock {
        override fun now(): Instant = Clock.System.now()
    }

    fun customNow(clock: Clock): Instant = clock.now()
    """

    @Test
    func testClockTopLevelObjectsAndSystemSupertypeResolve() throws {
        let ctx = makeContextFromSource(Self.source, emit: .executable)
        try runSema(ctx)
        #expect(
            ctx.diagnostics.diagnostics.isEmpty,
            "Unexpected Clock diagnostics: \(ctx.diagnostics.diagnostics)"
        )

        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let kotlinTime = [interner.intern("kotlin"), interner.intern("time")]
        let clockSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [interner.intern("Clock")]))
        let instantSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [interner.intern("Instant")]))
        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: clockSymbol))
        let systemSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("Clock"),
            interner.intern("System"),
        ]))

        #expect(sema.symbols.symbol(clockSymbol)?.kind == .interface)
        #expect(sema.symbols.symbol(companionSymbol)?.kind == .object)
        #expect(sema.symbols.parentSymbol(for: companionSymbol) == clockSymbol)
        #expect(sema.symbols.symbol(companionSymbol)?.fqName == kotlinTime + [
            interner.intern("Clock"),
            interner.intern("Companion"),
        ])
        #expect(
            sema.symbols.lookupAll(fqName: kotlinTime + [
                interner.intern("Clock"),
                interner.intern("Companion"),
            ]).count == 1
        )
        #expect(sema.symbols.symbol(systemSymbol)?.kind == .object)
        #expect(sema.symbols.parentSymbol(for: systemSymbol) == clockSymbol)
        #expect(sema.symbols.directSupertypes(for: systemSymbol) == [clockSymbol])
        #expect(sema.types.directNominalSupertypes(for: systemSymbol) == [clockSymbol])

        let clockType = sema.types.make(.classType(ClassType(
            classSymbol: clockSymbol,
            args: [],
            nullability: .nonNull
        )))
        let instantType = sema.types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))

        let localCompanionDecl = try #require(
            ctx.ast?.files
                .flatMap(\.topLevelDecls)
                .compactMap { ctx.ast?.arena.decl($0) }
                .compactMap { decl -> FunDecl? in
                    guard case let .funDecl(function) = decl, function.name == interner.intern("localCompanion") else {
                        return nil
                    }
                    return function
                }
                .first
        )
        guard case let .block(localStatements, _) = localCompanionDecl.body,
              let localDeclExpr = localStatements.first,
              case let .localDecl(_, _, _, initializer, _, _) = ctx.ast?.arena.expr(localDeclExpr),
              let initializer
        else {
            Issue.record("Expected local Companion declaration in the regression source")
            return
        }
        let initializerType = try #require(sema.bindings.exprType(for: initializer))
        #expect(
            initializerType == companionType,
            "Companion initializer inferred as \(sema.types.displayName(of: initializerType, symbols: sema.symbols, interner: interner))"
        )
        #expect(sema.bindings.identifierSymbol(for: initializer) == companionSymbol)

        let companionIdentity = try #require(sema.symbols.lookup(fqName: [interner.intern("companionIdentity")]))
        let systemAsClock = try #require(sema.symbols.lookup(fqName: [interner.intern("systemAsClock")]))
        let systemNow = try #require(sema.symbols.lookup(fqName: [interner.intern("systemNow")]))
        let customNow = try #require(sema.symbols.lookup(fqName: [interner.intern("customNow")]))
        #expect(sema.symbols.functionSignature(for: companionIdentity)?.returnType == companionType)
        #expect(sema.symbols.functionSignature(for: systemAsClock)?.returnType == clockType)
        #expect(sema.symbols.functionSignature(for: systemNow)?.returnType == instantType)
        #expect(sema.symbols.functionSignature(for: customNow)?.receiverType == nil)
        #expect(sema.symbols.functionSignature(for: customNow)?.parameterTypes == [clockType])
        #expect(sema.symbols.functionSignature(for: customNow)?.returnType == instantType)
    }
}
#endif
