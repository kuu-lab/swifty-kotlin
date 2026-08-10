#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testRuntimeBackedAndSourceBackedSequenceAggregateHOFs() throws {
        let sources = [
            """
            package sample0

            fun main0(): Int = maxOf(1, 2)
            """,
            """
            package sample1

            fun main1(values: Sequence<Int>): Int {
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
                return 0
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map { $0.message }
            #expect(
                !ctx.diagnostics.hasError,
                "Expected runtime-backed bundled stdlib / Sequence HOF source to compile without diagnostics, got: \(diagnosticMessages)"
            )

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            do {
                let functionNames = Set(findAllKIRFunctions(in: module).map { interner.resolve($0.name) })

                #expect(functionNames.contains("main0"), "Expected user entry point to be emitted")
                #expect(!functionNames.contains("maxOf"), "Expected bundled kotlin.comparisons.maxOf body to stay runtime-backed")
            }

            do {
                let mainBody = try findKIRFunctionBody(named: "main1", in: module, interner: interner)
                let sourceBackedCallees = Set(extractCallees(from: mainBody, interner: interner))
                for expected in ["associateBy", "groupBy"] {
                    #expect(
                        sourceBackedCallees.contains(expected),
                        "Expected Sequence.\(expected) to bind to bundled source, got: \(sourceBackedCallees.sorted())"
                    )
                }
            }
        }
    }

    @Test func testRuntimeBackedStdlibNameInUserSourceStillEmitsFunction() throws {
        let source = """
        package kotlin.comparisons

        fun maxOf(left: String, right: String): String = left

        fun main(): String = maxOf("left", "right")
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let diagnosticMessages = ctx.diagnostics.diagnostics.map { $0.message }
            #expect(
                !ctx.diagnostics.hasError,
                "Expected user-defined kotlin.comparisons.maxOf to compile without diagnostics, got: \(diagnosticMessages)"
            )

            let module = try #require(ctx.kir)
            let functionNames = Set(findAllKIRFunctions(in: module).map { ctx.interner.resolve($0.name) })

            #expect(functionNames.contains("main"), "Expected user entry point to be emitted")
            #expect(functionNames.contains("maxOf"), "Expected user-defined kotlin.comparisons.maxOf to be emitted")
        }
    }
}
#endif
