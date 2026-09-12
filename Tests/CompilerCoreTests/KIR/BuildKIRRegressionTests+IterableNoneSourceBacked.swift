#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test
    func iterableNoneDoesNotLowerToLegacyRuntimeBridges() throws {
        let source = """
        fun probe(values: Iterable<Int>): Boolean {
            val isEmpty = values.none()
            return isEmpty && values.none { it > 0 }
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected Iterable.none KIR to build cleanly"
        )

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
        let callees = extractCallees(from: body, interner: ctx.interner)
        #expect(callees.filter { $0 == "none" }.count == 2)
        #expect(!callees.contains("kk_sequence_none"))
        #expect(!callees.contains("kk_iterable_none"))
        #expect(!callees.contains("__kk_iterable_none"))
    }
}
#endif
