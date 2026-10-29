@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrimitiveBoundMemberOperatorTests {
    @Test
    func booleanComparableSupportsMemberCompareToAndRelationalOperators() throws {
        let ctx = makeContextFromSource("""
        fun compare(x: Boolean, y: Boolean): Int = x.compareTo(y)
        fun less(x: Boolean, y: Boolean): Boolean = x < y
        fun lessOrEqual(x: Boolean, y: Boolean): Boolean = x <= y
        fun greater(x: Boolean, y: Boolean): Boolean = x > y
        fun greaterOrEqual(x: Boolean, y: Boolean): Boolean = x >= y
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func numericBoundsSupportCompoundAndComparisonWithoutChangingUserOperators() throws {
        let ctx = makeContextFromSource("""
        fun <T : Int> shift(v: T): Char { var c = 'a'; c += v; return c }
        fun <T : Int> lower(v: T): Char { var c = 'b'; c -= v; return c }
        class Letters(var letter: Char)
        fun <T : Int> propertyShift(v: T): Char { val box = Letters('a'); box.letter += v; return box.letter }
        fun <T : Double> compound(v: T): Double { var result = 1.0; result += v; return result }
        fun <T : Float> floatCompound(v: T): Float { var result = 1.0f; result *= v; return result }
        fun <T : Long> longCompound(v: T): Long { var result = 1L; result += v; return result }
        fun <T : Int> compare(v: T): Int = v.compareTo(3.0)
        fun <T : Byte> byteCompare(v: T): Int = v.compareTo(3L)
        fun <T : Short> shortCompare(v: T): Int = v.compareTo(3.0f)
        fun <T : Int> T.compareTo(other: String): T = this
        fun <T : Int> extension(v: T): T = v.compareTo("tag")
        fun <T : Char> T.compareTo(other: Int): T = this
        fun <T : Char> charExtension(v: T): T = v.compareTo(3)
        class Counter(var result: Int) {
            operator fun plusAssign(other: Double) { result += 7 }
        }
        fun <T : Double> custom(v: T): Int { val c = Counter(0); c += v; return c.result }
        fun <T : Comparable<T>> generic(a: T, b: T): Int = a.compareTo(b)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nonNumericNullableAndUnsignedBoundariesRemainRejected() throws {
        let ctx = makeContextFromSource("""
        fun <T : Any> anyCompound(v: T) { var result = 1.0; result += v }
        fun <T : Number> numberCompound(v: T) { var result = 1.0; result += v }
        fun <T : Double?> nullableCompound(v: T) { var result = 1.0; result += v }
        fun <T : Int?> nullableCompare(v: T): Int = v.compareTo(3.0)
        fun <T : UInt> mixedCompound(v: T) { var result = 1; result += v }
        fun <T : Int> mixedCompare(v: T): Int = v.compareTo(3u)
        fun <T : Long> invalidCharLong(v: T) { var c = 'a'; c += v }
        fun <T : Byte> invalidCharByte(v: T) { var c = 'a'; c -= v }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }.count == 8,
                "\(ctx.diagnostics.diagnostics)")
    }
}
