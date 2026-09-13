#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendCharDirectionalityTests {

    @Test
    func testCodegenCharDirectionalityOrdinals() throws {
        let source = """
        fun main() {
            println('A'.directionality)
            println('\\u05D0'.directionality)
            println('5'.directionality)
            println(' '.directionality)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "CharDirectionalityOrdinals",
            expected:
                """
                1
                2
                4
                13
                """ + "\n"
        )
    }

    @Test
    func testCodegenCharDirectionalityArabic() throws {
        let source = """
        fun main() {
            println('\\u0627'.directionality)
        }
        """
        try assertKotlinOutput(source, moduleName: "CharDirectionalityArabic", expected: "3\n")
    }

}
#endif
