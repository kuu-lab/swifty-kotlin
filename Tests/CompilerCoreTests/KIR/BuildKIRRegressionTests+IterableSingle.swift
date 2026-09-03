#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    @Test func testIterableSingleFamilyUsesBundledSourceCalls() throws {
        let source = """
        fun probe(values: Iterable<Int?>): Int? {
            val single = values.single()
            val singlePredicate = values.single { it != null }
            val singleOrNull = values.singleOrNull()
            val singleOrNullPredicate = values.singleOrNull { it == null }
            return singleOrNull ?: singleOrNullPredicate ?: single
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Iterable.single-family source to compile, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let probeBody = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = extractCallees(from: probeBody, interner: ctx.interner)
            #expect(callees.contains("single"), "Expected non-inline Iterable.single call in KIR")
            #expect(callees.contains("singleOrNull"), "Expected non-inline Iterable.singleOrNull call in KIR")
            #expect(!callees.contains { $0.hasPrefix("kk_iterable_single") })
        }
    }
}
#endif
