#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testSequenceAggregateHOFsUseBundledSourceBackedCalls() throws {
        let source = """
        fun main(values: Sequence<Int>): Int {
            val folded = values.fold(0) { acc, value -> acc + value }
            val reduced = values.reduce { acc, value -> acc + value }
            val scanned = values.scan(0) { acc, value -> acc + value }
            val associated = values.associate { value -> Pair(value, value + 10) }
            val associatedBy = values.associateBy { value -> value % 2 }
            val associatedByValue = values.associateBy(
                { value -> value % 2 },
                { value -> value + 10 }
            )
            val grouped = values.groupBy { value -> value % 2 }
            val groupedValue = values.groupBy(
                { value -> value % 2 },
                { value -> value + 10 }
            )
            val summed = values.sumOf { value -> value }
            val maxValue = values.maxByOrNull { value -> value }
            val minValue = values.minByOrNull { value -> value }
            return 0
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Sequence aggregate HOF source to compile without diagnostics, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let sourceBackedCallees = Set(extractCallees(from: mainBody, interner: ctx.interner))
            let expectedSourceBackedCallees = [
                "fold",
                "reduce",
                "scan",
                "associate",
                "associateBy",
                "groupBy",
                "sumOf",
                "maxByOrNull",
                "minByOrNull",
            ]
            for expected in expectedSourceBackedCallees {
                #expect(
                    sourceBackedCallees.contains(expected),
                    "Expected Sequence.\(expected) to bind to bundled source, got: \(sourceBackedCallees.sorted())"
                )
            }

            try LoweringPhase().run(ctx)

            let loweredModule = try #require(ctx.kir)
            let loweredMainBody = try findKIRFunctionBody(named: "main", in: loweredModule, interner: ctx.interner)
            let loweredCallees = Set(extractCallees(from: loweredMainBody, interner: ctx.interner))
            let runtimeAggregateCallees = [
                "kk_sequence_fold",
                "kk_sequence_reduce",
                "kk_sequence_scan",
                "kk_sequence_associate",
                "kk_sequence_associateBy",
                "kk_sequence_groupBy",
                "kk_sequence_sumOf",
                "kk_sequence_maxByOrNull",
                "kk_sequence_minByOrNull",
            ]
            for runtimeCallee in runtimeAggregateCallees {
                #expect(
                    !loweredCallees.contains(runtimeCallee),
                    "Expected Sequence aggregate HOF call to bypass \(runtimeCallee), got: \(loweredCallees.sorted())"
                )
            }
        }
    }
}
#endif
