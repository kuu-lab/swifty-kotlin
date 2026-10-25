#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IndexedNumericArrayIncrementTests {
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
