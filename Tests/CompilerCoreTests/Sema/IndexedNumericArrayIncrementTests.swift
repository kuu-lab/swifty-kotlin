#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct IndexedNumericArrayIncrementTests {
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
