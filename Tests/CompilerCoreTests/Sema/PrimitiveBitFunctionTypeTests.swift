@testable import CompilerCore
import Testing

@Suite
struct PrimitiveBitFunctionTypeTests {

    // MARK: - Shared Sema context

    private static let sharedSources: [String] = [
        """
        package sample0
        fun probe(value: Long): Long {
            val highest: Long = value.highestOneBit()
            val lowest: Long = value.lowestOneBit()
            val takenHighest: Long = value.takeHighestOneBit()
            val takenLowest: Long = value.takeLowestOneBit()
            val bitCount: Int = value.countOneBits()
            return highest + lowest + takenHighest + takenLowest + bitCount.toLong()
        }
        """,
        """
        package sample1
        fun probe(value: Long, scale: Double): Long {
            var accumulated = value
            accumulated -= 1L
            accumulated += 2L
            accumulated *= 3L
            var scaled = scale
            scaled /= 2.0
            return (accumulated and 0xFFL) + scaled.toLong()
        }
        """
    ]

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }
    @Test func testLongBitExtractionFunctionsPreserveLongResultType() throws {

        let ctx = try sharedCtx()
            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                Comment(rawValue: "Long bit functions should preserve their Kotlin result types, got: \(ctx.diagnostics.diagnostics)")
            )

    }

    /// BUG-015: an arithmetic compound assignment used to demote the target local to
    /// `Int`, so later `Long` member calls such as `value and 0xFFL` failed to resolve.
    @Test func testCompoundAssignmentPreservesNonIntNumericLocalTypes() throws {

        let ctx = try sharedCtx()
            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                Comment(rawValue: "Compound assignment should preserve Long/Double local types, got: \(ctx.diagnostics.diagnostics)")
            )

    }
}
