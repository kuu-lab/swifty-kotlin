#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test
    func iterablePartitionDoesNotLowerToLegacyPartitionBridge() throws {
        let source = """
        fun probe(values: Iterable<Int>): Pair<List<Int>, List<Int>> {
            return values.partition { it % 2 == 0 }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Iterable.partition KIR to build, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "probe", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))
            #expect(!callees.contains("kk_list_partition"))
            #expect(!callees.contains("kk_iterable_partition"))
            #expect(!callees.contains("__kk_iterable_partition"))
        }
    }
}
#endif
