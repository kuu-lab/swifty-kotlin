#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct IndexedNumericArrayIncrementTests {
    @Test
    func genericIndexedGetSetAcceptsNumericIncrementAndDecrement() throws {
        let ctx = makeContextFromSource("""
        class A<T>(var value: T) {
            operator fun get(i: Int) = value
            operator fun set(i: Int, newValue: T) { value = newValue }
        }
        fun updateIndexedNumbers() {
            val aByte = A<Byte>(1)
            val aShort = A<Short>(1)
            val aInt = A<Int>(1)
            val aLong = A<Long>(1)
            val aFloat = A<Float>(1.0f)
            val aDouble = A<Double>(1.0)

            aByte[0]++
            aByte[0]--
            aShort[0]++
            aShort[0]--
            aInt[0]++
            aInt[0]--
            aLong[0]++
            aLong[0]--
            aFloat[0]++
            aFloat[0]--
            aDouble[0]++
            aDouble[0]--
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func indexedLongAndDoubleCompoundAssignmentsAcceptIntLiterals() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val longs = mutableListOf(0L, 0L, 0L)
            longs[1] += 5
            val doubles = mutableListOf(0.0, 0.0)
            doubles[1] += 5
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitIndexedCompoundAssignmentStillChecksRightHandType() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val values = byteArrayOf(1)
            values[0] += 1L
        }
        """)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: ctx)
    }

    @Test
    func indexedSmallIntegerArrayIncrementAndDecrementTypecheck() throws {
        let ctx = makeContextFromSource("""
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            val bytes = byteArrayOf(127, -128)
            bytes[0]++
            bytes[1]--
            val shorts = shortArrayOf(32767, -32768)
            shorts[0]++
            shorts[1]--
            val ubytes = ubyteArrayOf(255u, 0u)
            ubytes[0]++
            ubytes[1]--
            val ushorts = ushortArrayOf(65535u, 0u)
            ushorts[0]++
            ushorts[1]--
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
