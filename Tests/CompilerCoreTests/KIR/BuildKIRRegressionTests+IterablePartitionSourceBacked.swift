#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func iterablePartitionDoesNotLowerToLegacyPartitionBridge() throws {
        let source = """
        fun probe(values: Iterable<Int>): Pair<List<Int>, List<Int>> {
            return values.partition { it % 2 == 0 }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected Iterable.partition KIR to build, got: \(ctx.diagnostics.diagnostics.map(\.message))"
        )

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        try expectSourceBackedCalls(
            named: KnownCompilerNames(interner: ctx.interner).partition,
            in: body, context: ctx, count: 1
        )
        try expectResolvedKIRCallTargets(in: body, context: ctx)
    }
}
#endif
