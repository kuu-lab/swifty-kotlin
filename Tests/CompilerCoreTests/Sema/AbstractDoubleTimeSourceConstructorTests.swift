#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AbstractDoubleTimeSourceConstructorTests {
    @Test
    func constructorMatchesKotlin2310VisibilityAndSignature() throws {
        let source = """
        @file:Suppress("DEPRECATION", "DEPRECATION_ERROR")

        import kotlin.time.AbstractDoubleTimeSource
        import kotlin.time.DurationUnit
        import kotlin.time.ExperimentalTime

        @OptIn(ExperimentalTime::class)
        abstract class Probe : AbstractDoubleTimeSource(DurationUnit.MILLISECONDS)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.isEmpty)

        let sema = try #require(ctx.sema)
        let kotlinTime = ["kotlin", "time"].map { ctx.interner.intern($0) }
        let ownerSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            ctx.interner.intern("AbstractDoubleTimeSource"),
        ]))
        let ownerType = sema.types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        let durationUnitSymbol = try #require(sema.symbols.lookup(fqName: kotlinTime + [
            ctx.interner.intern("DurationUnit"),
        ]))
        let durationUnitType = sema.types.make(.classType(ClassType(
            classSymbol: durationUnitSymbol,
            args: [],
            nullability: .nonNull
        )))
        let constructorSymbol = try #require(sema.symbols.lookupAll(
            fqName: kotlinTime + [
                ctx.interner.intern("AbstractDoubleTimeSource"),
                ctx.interner.intern("<init>"),
            ]
        ).first { sema.symbols.symbol($0)?.kind == .constructor })
        let constructorInfo = try #require(sema.symbols.symbol(constructorSymbol))
        #expect(constructorInfo.visibility == .public)

        let signature = try #require(sema.symbols.functionSignature(for: constructorSymbol))
        #expect(signature.receiverType == ownerType)
        #expect(signature.parameterTypes == [durationUnitType])
        #expect(signature.returnType == ownerType)
    }
}
#endif
