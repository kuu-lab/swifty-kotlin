@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSingleUsesRuntimeHelper() throws {
        let source = """
        fun printSingle(values: List<Int>) {
            println(values.single())
        }

        fun main() {
            printSingle(listOf(42))
            println(listOf("only").single())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionSingle", expected: "42\nonly\n")
    }
}

