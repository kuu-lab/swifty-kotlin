@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionDistinctByEdgeCases() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4, 5)
            println(values.distinctBy { it % 2 })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionDistinctByEdgeCases", expected: "[1, 2]\n")
    }
}

