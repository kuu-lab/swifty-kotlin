@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRandomOrNullReadsCollectionReceivers() throws {
        let source = """
        fun main() {
            println(setOf("solo").randomOrNull())
            println(emptySet<Int>().randomOrNull() == null)
            val values: Collection<Int> = setOf(7)
            println(values.randomOrNull())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionRandomOrNullEdgeCases", expected: "solo\ntrue\n7\n")
    }
}

