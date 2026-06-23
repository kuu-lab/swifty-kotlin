@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
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

    func testCodegenCharDirectionalityArabic() throws {
        let source = """
        fun main() {
            println('\\u0627'.directionality)
        }
        """
        try assertKotlinOutput(source, moduleName: "CharDirectionalityArabic", expected: "3\n")
    }
}

