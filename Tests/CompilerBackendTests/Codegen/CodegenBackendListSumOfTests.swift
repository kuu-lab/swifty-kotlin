@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendListSumOfTests {

    @Test
    func testCodegenListSumOfUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.sumOf { it * 2 })
            println(emptyList<Int>().sumOf { it * 10 })
            println(values.sumOf { it.toLong() })
            println(values.sumOf { it.toDouble() })
            println(emptyList<Int>().sumOf { it.toLong() })
            println(emptyList<Int>().sumOf { it.toDouble() })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSumOfRuntime", expected: "12\n0\n6\n6.0\n0\n0.0\n")
    }
}
#endif
