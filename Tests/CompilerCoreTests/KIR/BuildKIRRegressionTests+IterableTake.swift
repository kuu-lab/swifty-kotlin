#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func iterableTakeFamilyLowersThroughBundledKotlinSource() throws {
        let source = """
        fun probe(values: Iterable<Int>): List<Int> {
            val prefix = values.take(2)
            return values.takeWhile { it > 0 }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        let callees = Set(extractCallees(from: body, interner: ctx.interner))

        #expect(callees.contains("take"), "Expected Iterable.take to remain a bundled Kotlin callee")
        try expectSourceBackedCalls(
            named: KnownCompilerNames(interner: ctx.interner).take, in: body, context: ctx, count: 1
        )
        try expectSourceBackedCalls(named: ctx.interner.intern("takeWhile"), in: body, context: ctx, count: 1)
        try expectResolvedKIRCallTargets(in: body, context: ctx)
    }
}
#endif
