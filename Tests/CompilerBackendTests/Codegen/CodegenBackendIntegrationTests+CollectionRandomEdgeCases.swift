@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRandomReadsCollectionReceivers() throws {
        let source = """
        fun main() {
            println(setOf("solo").random())
            val values: Collection<Int> = setOf(7)
            println(values.random())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionRandomEdgeCases", expected: "solo\n7\n")
    }
}

