@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionPlusHandlesListAndMapVariants() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2)
            println(values + 3)
            println(values + listOf(4, 5))

            val map = mapOf("a" to 1)
            val added = map + ("b" to 2)
            val overwritten = added + ("a" to 9)
            println(added)
            println(overwritten)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionPlusEdgeCases", expected: "[1, 2, 3]\n[1, 2, 4, 5]\n{a=1, b=2}\n{a=9, b=2}\n")
    }
}

