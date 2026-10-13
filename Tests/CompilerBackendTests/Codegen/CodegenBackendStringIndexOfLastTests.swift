#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendStringIndexOfLastTests {

    @Test
    func testCodegenStringIndexOfLastUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            println("abcabc".indexOfLast { it == 'b' })
            println("abcabc".indexOfLast { it == 'z' })
            println("hello".indexOfLast { it == 'l' })
            println("".indexOfLast { it == 'a' })
        }
        """

        try assertKotlinOutput(source, moduleName: "StringIndexOfLastRuntime", expected: "4\n-1\n3\n-1\n")
    }
}
#endif
