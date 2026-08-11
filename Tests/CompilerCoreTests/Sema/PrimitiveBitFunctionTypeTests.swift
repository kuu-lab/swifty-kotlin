@testable import CompilerCore
import Testing

@Suite
struct PrimitiveBitFunctionTypeTests {
    @Test
    func testLongBitExtractionFunctionsPreserveLongResultType() throws {
        let source = """
        fun probe(value: Long): Long {
            val highest: Long = value.highestOneBit()
            val lowest: Long = value.lowestOneBit()
            val takenHighest: Long = value.takeHighestOneBit()
            val takenLowest: Long = value.takeLowestOneBit()
            val bitCount: Int = value.countOneBits()
            return highest + lowest + takenHighest + takenLowest + bitCount.toLong()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                Comment(rawValue: "Long bit functions should preserve their Kotlin result types, got: \(ctx.diagnostics.diagnostics)")
            )
        }
    }

    /// BUG-015: an arithmetic compound assignment used to demote the target local to
    /// `Int`, so later `Long` member calls such as `value and 0xFFL` failed to resolve.
    @Test
    func testCompoundAssignmentPreservesNonIntNumericLocalTypes() throws {
        let source = """
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

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(
                ctx.diagnostics.diagnostics.isEmpty,
                Comment(rawValue: "Compound assignment should preserve Long/Double local types, got: \(ctx.diagnostics.diagnostics)")
            )
        }
    }
}
