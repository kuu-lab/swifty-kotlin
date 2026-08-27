#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TimeSourceNominalSurfaceTests {
    private static let source = """
    import kotlin.time.ExperimentalTime
    import kotlin.time.TimeSource

    fun companionProbe() = TimeSource.Companion
    fun companionIdentity() = TimeSource.Companion === TimeSource.Companion

    @OptIn(ExperimentalTime::class)
    fun monotonicProbe() = TimeSource.Monotonic.markNow()
    """

    @Test func testTimeSourceNominalSurfacesMatchKotlinContract() throws {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: Self.source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let (sema, interner) = try #require(result)
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let timeSourceSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
        ]))

        let companionSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
            interner.intern("Companion"),
        ]))
        #expect(sema.symbols.symbol(companionSymbol)?.kind == .object)
        #expect(sema.symbols.parentSymbol(for: companionSymbol) == timeSourceSymbol)
        #expect(sema.symbols.companionObjectSymbol(for: timeSourceSymbol) == companionSymbol)
        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        let companionProbe = try #require(sema.symbols.lookup(fqName: [interner.intern("companionProbe")]))
        let companionProbeSignature = try #require(sema.symbols.functionSignature(for: companionProbe))
        #expect(companionProbeSignature.returnType == companionType)
        let companionIdentity = try #require(sema.symbols.lookup(fqName: [interner.intern("companionIdentity")]))
        let companionIdentitySignature = try #require(sema.symbols.functionSignature(for: companionIdentity))
        #expect(companionIdentitySignature.returnType == sema.types.booleanType)

        let withComparableMarksSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
            interner.intern("WithComparableMarks"),
        ]))
        #expect(sema.symbols.symbol(withComparableMarksSymbol)?.kind == .interface)
        #expect(sema.symbols.parentSymbol(for: withComparableMarksSymbol) == timeSourceSymbol)
        #expect(sema.symbols.directSupertypes(for: withComparableMarksSymbol) == [timeSourceSymbol])

        let monotonicSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
            interner.intern("Monotonic"),
        ]))
        #expect(sema.symbols.symbol(monotonicSymbol)?.kind == .object)
        #expect(sema.symbols.parentSymbol(for: monotonicSymbol) == timeSourceSymbol)
        let monotonicInterfaceSupertypes = sema.symbols.directSupertypes(for: monotonicSymbol).filter {
            sema.symbols.symbol($0)?.kind == .interface
        }
        #expect(monotonicInterfaceSupertypes == [withComparableMarksSymbol])

        let valueTimeMarkSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            interner.intern("TimeSource"),
            interner.intern("Monotonic"),
            interner.intern("ValueTimeMark"),
        ]))
        let valueTimeMarkType = sema.types.make(.classType(ClassType(
            classSymbol: valueTimeMarkSymbol,
            args: [],
            nullability: .nonNull
        )))
        let monotonicProbe = try #require(sema.symbols.lookup(fqName: [interner.intern("monotonicProbe")]))
        let monotonicProbeSignature = try #require(sema.symbols.functionSignature(for: monotonicProbe))
        #expect(monotonicProbeSignature.returnType == valueTimeMarkType)
    }
}
#endif
