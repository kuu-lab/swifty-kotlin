#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SignedPrimitiveRangeToTests {
    @Test
    func signedPrimitiveRangeToOverloadsMatchRangeOperatorTypes() throws {
        let ctx = makeContextFromSource("""
        fun byteToByte(start: Byte, end: Byte): IntRange = start.rangeTo(end)
        fun byteToShort(start: Byte, end: Short): IntRange = start.rangeTo(end)
        fun byteToInt(start: Byte, end: Int): IntRange = start.rangeTo(end)
        fun byteToLong(start: Byte, end: Long): LongRange = start.rangeTo(end)
        fun shortToByte(start: Short, end: Byte): IntRange = start.rangeTo(end)
        fun shortToShort(start: Short, end: Short): IntRange = start.rangeTo(end)
        fun shortToInt(start: Short, end: Int): IntRange = start.rangeTo(end)
        fun shortToLong(start: Short, end: Long): LongRange = start.rangeTo(end)
        fun intToByte(start: Int, end: Byte): IntRange = start.rangeTo(end)
        fun intToShort(start: Int, end: Short): IntRange = start.rangeTo(end)
        fun intToInt(start: Int, end: Int): IntRange = start.rangeTo(end)
        fun intToLong(start: Int, end: Long): LongRange = start.rangeTo(end)
        fun longToByte(start: Long, end: Byte): LongRange = start.rangeTo(end)
        fun longToShort(start: Long, end: Short): LongRange = start.rangeTo(end)
        fun longToInt(start: Long, end: Int): LongRange = start.rangeTo(end)
        fun longToLong(start: Long, end: Long): LongRange = start.rangeTo(end)

        fun operatorByteToShort(start: Byte, end: Short): IntRange = start..end
        fun operatorByteToLong(start: Byte, end: Long): LongRange = start..end
        fun operatorShortToInt(start: Short, end: Int): IntRange = start..end
        fun operatorShortToLong(start: Short, end: Long): LongRange = start..end
        fun operatorIntToByte(start: Int, end: Byte): IntRange = start..end
        fun operatorIntToLong(start: Int, end: Long): LongRange = start..end
        fun operatorLongToShort(start: Long, end: Short): LongRange = start..end
        fun operatorLongToInt(start: Long, end: Int): LongRange = start..end
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func signedPrimitiveRangeToRejectsUnrelatedArgumentTypes() throws {
        let ctx = makeContextFromSource("""
        fun invalid(start: Byte) = start.rangeTo("not a number")
        """)

        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected Byte.rangeTo(String) to be rejected")
    }

    @Test(arguments: [
        "'a'..1.5",
        "'a'..1",
        "1..'a'",
        "1..1.5",
        "1.0..2f",
        "1f..2",
        "1u..5uL",
        "'a' downTo 1",
        "1.0 downTo 0.5",
    ])
    func rangeOperatorRejectsMismatchedOperandPair(expr: String) throws {
        let ctx = makeContextFromSource("""
        fun invalid() = \(expr)
        """)

        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected `\(expr)` to be rejected")
    }

    @Test
    func rangeOperatorAcceptsMatchingOperandPairs() throws {
        let ctx = makeContextFromSource("""
        fun ok() {
            val a = 'a'..'z'
            val b = 1..10
            val c = 1..10L
            val d = 1L..5
            val e = 1.0..5.0
            val f = 1f..5f
            val g = 1u..10u
            val h = 5 downTo 1
            val i = 'z' downTo 'a'
            val j = 1..<10
            val k = 'a'..<'z'
        }
        """)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
