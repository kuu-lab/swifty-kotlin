#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendTopLevelIfInitializersTests {

    @Test
    func testCodegenMultipleBranchingTopLevelInitializersRunCorrectly() throws {
        let source = """
        val a = if (1 > 2) 1 else 2
        val b = if (1 < 2) 3 else 4
        val c = when {
            a > b -> 100
            a < b -> 200
            else -> 300
        }
        var d = if (c == 200) a * b else 0

        fun main() {
            println(a)
            println(b)
            println(c)
            if (a < b) {
                d = d + 1
            } else {
                d = d - 1
            }
            println(d)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelIfInitializersRuntime",
            expected: "2\n3\n200\n7\n"
        )
    }

    @Test
    func testCodegenRepeatedStringTopLevelPropertyReadsStayValid() throws {
        let source = """
        val s = if (1 > 2) "gt" else "eq"
        val n = s.length

        fun main() {
            println(s.length)
            println(s)
            println(n)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "TopLevelStringPropertyReadRuntime",
            expected: "2\neq\n2\n"
        )
    }
}
#endif
