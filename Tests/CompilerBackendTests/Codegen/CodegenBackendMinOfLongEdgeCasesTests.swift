#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

// STDLIB-COMP-FN-044: minOf(Long, Long) — 2-arg Long overload end-to-end codegen tests.
@Suite
struct CodegenBackendMinOfLongEdgeCasesTests {

    @Test
    func testCodegenCompilesMinOfLongEdgeCases() throws {
        let source = """
        fun main() {
            println(minOf(3L, 7L))
            println(minOf(-10L, -3L))
            println(minOf(0L, 0L))
            println(minOf(Long.MIN_VALUE, Long.MAX_VALUE))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MinOfLongEdgeCases",
            expected: """
            3
            -10
            0
            -9223372036854775808

            """
        )
    }

    @Test
    func testCodegenMinOfLongReturnsCorrectType() throws {
        let source = """
        fun minLong(a: Long, b: Long): Long = minOf(a, b)

        fun main() {
            val result: Long = minLong(100L, 200L)
            println(result)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MinOfLongReturnType",
            expected: "100\n"
        )
    }
}
#endif
