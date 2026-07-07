#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    @Test func testRuntimeBackedBundledStdlibFunctionsAreNotEmittedIntoConsumerKIR() throws {
        let source = """
        fun main(): Int = maxOf(1, 2)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected runtime-backed bundled stdlib call to compile without diagnostics, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let functionNames = Set(findAllKIRFunctions(in: module).map { ctx.interner.resolve($0.name) })

            #expect(functionNames.contains("main"), "Expected user entry point to be emitted")
            #expect(!functionNames.contains("maxOf"), "Expected bundled kotlin.comparisons.maxOf body to stay runtime-backed")
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
            #expect(
                !ctx.diagnostics.hasError,
                "Expected user-defined kotlin.comparisons.maxOf to compile without diagnostics, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let functionNames = Set(findAllKIRFunctions(in: module).map { ctx.interner.resolve($0.name) })

            #expect(functionNames.contains("main"), "Expected user entry point to be emitted")
            #expect(functionNames.contains("maxOf"), "Expected user-defined kotlin.comparisons.maxOf to be emitted")
        }
    }

    @Test func testSequenceAggregateHOFsUseBundledSourceBackedCalls() throws {
        let source = """
        fun main(values: Sequence<Int>): Int {
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
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "Expected Sequence association/groupBy source to compile without diagnostics, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let sourceBackedCallees = Set(extractCallees(from: mainBody, interner: ctx.interner))
            for expected in ["associateBy", "groupBy"] {
                #expect(
                    sourceBackedCallees.contains(expected),
                    "Expected Sequence.\(expected) to bind to bundled source, got: \(sourceBackedCallees.sorted())"
                )
            }
        }
    }
}
#endif
