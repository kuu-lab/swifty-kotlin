#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1093: execute the source-backed size and copy overloads and verify copy isolation.
@Suite
struct AtomicLongArraySourceMigrationCodegenTests {
    @Test
    func testAtomicLongArrayConstructorsPreserveAllocationAndCopySemantics() throws {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        @file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

        import kotlin.concurrent.AtomicLongArray

        fun main() {
            val zeros = AtomicLongArray(2)
            val source = longArrayOf(4, 5)
            val copied = AtomicLongArray(source)
            source[0] = 99
            println(zeros.size)
            println(copied[0])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AtomicLongArraySourceConstructors",
            expected: "2\n4\n",
            // The copy overload is @PublishedApi internal and intentionally
            // omitted from consumer .kklib metadata. Compile bundled sources to
            // verify this implementation path without changing that contract.
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
