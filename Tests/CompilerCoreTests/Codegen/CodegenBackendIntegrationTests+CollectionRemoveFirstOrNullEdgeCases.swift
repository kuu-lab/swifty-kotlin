@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveFirstOrNullMutatesMutableList() throws {
        let source = """
        fun main() {
            val values = mutableListOf(10, 20)
            println(values.removeFirstOrNull() ?: -1)
            println(values)
            println(values.removeFirstOrNull() ?: -1)
            println(values)
            println(values.removeFirstOrNull() ?: -1)
            println(values)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRemoveFirstOrNullEdgeCases",
            expected:
                """
                10
                [20]
                20
                []
                -1
                []
                """ + "\n"
        )
    }
}

