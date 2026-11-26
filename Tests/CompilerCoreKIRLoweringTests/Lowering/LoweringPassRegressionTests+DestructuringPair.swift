#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {
    @Test
    func testPairDestructuringAfterPartitionEmitsComponentNCalls() throws {
        let source = """
        fun main(): Int {
            val (evens, odds) = listOf(1, 2, 3, 4).partition { it % 2 == 0 }
            return evens.size + odds.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "PairDestructuringPartition",
                emit: .kirDump
            )
            try runToLowering(ctx)

            #expect(
                !ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
                "Expected no errors, got: \(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })"
            )

            let module = try #require(ctx.kir, "KIR module must be present after lowering")

            var allCallees: [String] = []
            for function in findAllKIRFunctions(in: module) {
                allCallees.append(contentsOf: extractCallees(from: function.body, interner: ctx.interner))
            }

            #expect(
                allCallees.contains("component1"),
                "Expected component1() call for the first component; callees: \(allCallees)"
            )
            #expect(
                allCallees.contains("component2"),
                "Expected component2() call for the second component; callees: \(allCallees)"
            )

            #expect(
                allCallees.contains(RuntimeCall.listSize.name),
                "Expected __kk_list_size for evens.size / odds.size; callees: \(allCallees)"
            )
        }
    }

    @Test
    func testPairDestructuringAfterPartitionHasNoSemaDiagnostics() throws {
        let source = """
        fun main(): Int {
            val (evens, odds) = listOf(1, 2, 3, 4).partition { it % 2 == 0 }
            return evens.size + odds.size
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "PairDestructuringSema")
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error }),
                "Expected no sema errors after partition destructuring fix, got: \(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map { "\($0.code): \($0.message)" })"
            )
        }
    }
}
#endif
