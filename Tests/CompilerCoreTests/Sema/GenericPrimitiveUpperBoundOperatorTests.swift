@testable import CompilerCore
import Testing

@Suite
struct GenericPrimitiveUpperBoundOperatorTests {

    @Test
    func multiplicationUsesConcretePrimitiveUpperBound() throws {
        let ctx = makeContextFromSource("""
        fun <T : Double> f(v: T) = v * v
        fun use(value: Double): Double = f(value)
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let function = try #require(sema.symbols.lookupAll(
            fqName: [ctx.interner.intern("f")]
        ).first { sema.symbols.functionSignature(for: $0) != nil })
        #expect(sema.symbols.functionSignature(for: function)?.returnType == sema.types.doubleType)
    }
    @Test(arguments: [
        "fun <T : Double?> f(v: T): Double = v!! * v!!",
        "fun <T : Double?> f(v: T): Double = if (v != null) v * v else 0.0",
    ])
    func nonNullEvidenceAllowsNullablePrimitiveUpperBounds(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun <T : Double?> f(v: T) = v * v",
        "fun <T : Number?> f(v: T) = v!! * v!!",
        "fun <T : Any?> f(v: T) = v!! * v!!",
    ])
    func nonNullEvidenceDoesNotInventNumericBounds(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [
        "fun <T : Double?, U : T?> f(v: U): Double = v!! * v!!",
        "fun <T : Double?, U : T?> f(v: U): Double = if (v != null) v * v else 0.0",
    ])
    func nonNullEvidenceTraversesNullableTypeParameterBounds(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun <T : Double?, U : T?> f(v: U) = v * v",
        "fun <T : Number?, U : T?> f(v: U) = v!! * v!!",
    ])
    func nullableTypeParameterBoundsStillRequireNumericEvidence(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
    }

}
