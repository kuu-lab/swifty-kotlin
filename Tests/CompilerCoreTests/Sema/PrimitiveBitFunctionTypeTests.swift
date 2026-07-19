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
}
