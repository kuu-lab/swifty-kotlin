#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    /// KSP-1475: TimeSource measurement APIs remain bundled Kotlin calls in user KIR.
    @Test func testTimeSourceMeasureCallsLowerToBundledKotlinCallees() throws {
        let source = """
        import kotlin.time.ExperimentalTime
        import kotlin.time.TimeSource
        import kotlin.time.measureTime
        import kotlin.time.measureTimedValue

        @OptIn(ExperimentalTime::class)
        fun main() {
            val source: TimeSource = TimeSource.Monotonic
            source.measureTime { }
            source.measureTimedValue { "value" }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(callees.contains("measureTime"), "Expected a call to bundled TimeSource.measureTime")
            #expect(
                callees.contains("measureTimedValue"),
                "Expected a call to bundled TimeSource.measureTimedValue"
            )
            #expect(!callees.contains("__kk_time_source_mark_now"))
        }
    }
}
#endif
