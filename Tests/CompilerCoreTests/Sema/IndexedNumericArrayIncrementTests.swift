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
}
#endif
