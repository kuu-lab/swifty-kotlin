#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

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

    // KUU-4056: kotlin.ranges declares `step` only on the progression/range
    // classes, so kotlinc reports "unresolved reference 'step'" on plain
    // scalar receivers. The builtin infix path used to type `i step 2` as an
    // Int progression anyway.
    @Test(arguments: [
        "5",
        "5L",
        "'a'",
        "1.5",
        "5u",
    ])
    func infixStepRejectsScalarReceivers(receiver: String) throws {
        let ctx = makeContextFromSource("""
        fun test() {
            val p = \(receiver) step 2
            println(p)
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0024" }, "\(errors)")
    }

    @Test
    func infixStepRejectsScalarVariableReceivers() throws {
        let ctx = makeContextFromSource("""
        fun test(i: Int, l: Long, c: Char, d: Double) {
            val a = i step 2
            val b = l step 2L
            val cc = c step 2
            val dd = d step 2
        }
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 4, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0024" }, "\(errors)")
    }

    @Test
    func infixStepKeepsRangeAndProgressionReceivers() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        fun test() {
            val stepped = 1..10 step 2
            val down = 10 downTo 1 step 2
            val until = 1 until 10 step 2
            val open = 1..<10 step 2
            val uint = 1u..10u step 2
            val ulong = 1uL..10uL step 2
            val chars = 'a'..'z' step 2
            val longs = 1L..10L step 2L
            val held = 1..10
            val heldStep = held step 2
            var heldVar = 1..10
            val heldVarStep = heldVar step 2
            val progression: IntProgression = 1..10 step 2
            val restep = progression step 3
            for (x in 1..10 step 2) {
                println(x)
            }
        }
        """, allowDefaultStdlibLibrary: true)

        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
