@testable import CompilerCore
import Testing

@Suite
struct NarrowPrimitiveCompareToTests {
    @Test
    func byteAndShortResolveAllSignedNumericArgumentsAndComparableBounds() throws {
        let ctx = makeContextFromSource("""
        fun <T : Comparable<T>> compare(a: T, b: T): Int = a.compareTo(b)
        fun parity(b: Byte, s: Short, i: Int, l: Long, f: Float, d: Double) {
            val results: List<Int> = listOf(
                b.compareTo(b), b.compareTo(s), b.compareTo(i),
                b.compareTo(l), b.compareTo(f), b.compareTo(d),
                s.compareTo(b), s.compareTo(s), s.compareTo(i),
                s.compareTo(l), s.compareTo(f), s.compareTo(d),
                compare(b, b), compare(s, s)
            )
            val byteComparable: Comparable<Byte> = b
            val shortComparable: Comparable<Short> = s
            byteComparable.compareTo(b)
            shortComparable.compareTo(s)
            val nullableByte: Byte? = b
            val nullableShort: Short? = s
            val byteResult: Int? = nullableByte?.compareTo(d)
            val shortResult: Int? = nullableShort?.compareTo(l)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nonNumericArgumentsAreRejected() throws {
        let ctx = makeContextFromSource("""
        fun invalid(b: Byte, s: Short) {
            b.compareTo("1")
            s.compareTo(true)
            b.compareTo('a')
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 3, "\(errors)")
    }
}
