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
}
