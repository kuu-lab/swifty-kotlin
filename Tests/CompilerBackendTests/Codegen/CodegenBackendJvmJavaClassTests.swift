#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendJvmJavaClassTests {

    @Test
    func testJavaClassInvocationOnAnyReturnsNonNull() throws {
        let source = """
        fun main() {
            val n = 42
            val c = n.javaClass()
            println(c != null)
        }
        """
        try assertKotlinOutput(source, moduleName: "JvmJavaClassTest", expected: "true\n")
    }
}
#endif
