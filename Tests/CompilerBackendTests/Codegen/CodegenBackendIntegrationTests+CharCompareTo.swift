@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // PARITY-CODEGEN-005: Char.compareTo(Char)
    func testCodegenCompilesCharCompareTo() throws {
        let source = """
        fun main() {
            println('Z'.compareTo('A'))
            println('A'.compareTo('Z'))
            println('A'.compareTo('A'))
        }
        """
        try assertKotlinOutput(source, moduleName: "CharCompareTo", expected: "25\n-25\n0\n")
    }
}

