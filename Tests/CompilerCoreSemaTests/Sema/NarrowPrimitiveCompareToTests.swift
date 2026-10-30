@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

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
            val comparator: (Byte, Double) -> Int = { a, b -> a.compareTo(b) }
            val lambdaResult: Int = comparator(-128, -127.5)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nonNumericArgumentsAreRejected() throws {
        let ctx = makeContextFromSource("""
        fun invalid(b: Byte, s: Short, nullable: Int?) {
            b.compareTo("1")
            s.compareTo(true)
            b.compareTo('a')
            s.compareTo(nullable)
            b.compareTo(1u)
            s.compareTo(null)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 6, "\(errors)")
    }

    @Test
    func userDefinedNonNumericCompareToExtensionStillResolves() throws {
        let ctx = makeContextFromSource("""
        fun Byte.compareTo(other: String): Int = 0
        fun Short.compareTo(other: Boolean): Int = 0
        fun parity(b: Byte, s: Short) {
            b.compareTo("1")
            s.compareTo(true)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    /// KUU-3143: `kotlin.UInt`/`ULong`/`UByte`/`UShort` FQ names collide with
    /// the bundled `fun UInt(data: Int)`-style constructor helpers. On the
    /// precompiled stdlib artifact path the imported index materializes the
    /// function ahead of the class, so primitive member lookup must prefer the
    /// nominal class symbol rather than the first entry at the FQ name.
    @Test(arguments: [false, true])
    func unsignedPrimitiveMemberCallsResolve(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary {
            TestStdlibCache.shared.prepare()
        }
        let ctx = makeContextFromSource("""
        @OptIn(ExperimentalUnsignedTypes::class)
        fun checkUnsignedMembers() {
            val r1: Int = 1u.compareTo(2u)
            val r2: Int = 1uL.compareTo(2uL)
            val r3: Int = 1.toUByte().compareTo(2.toUByte())
            val r4: Int = 1.toUShort().compareTo(2.toUShort())
            val m: UInt = uintArrayOf(1u, 2u).max()
            val n: UInt = uintArrayOf(1u, 2u).min()
        }
        """, allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
