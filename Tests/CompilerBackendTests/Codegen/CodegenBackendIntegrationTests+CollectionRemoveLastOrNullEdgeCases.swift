@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveLastOrNullMutatesMutableList() throws {
        let source = """
        fun main() {
            val values = mutableListOf(10, 20)
            println(values.removeLastOrNull() ?: -1)
            println(values)
            println(values.removeLastOrNull() ?: -1)
            println(values)
            println(values.removeLastOrNull() ?: -1)
            println(values)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRemoveLastOrNullEdgeCases",
            expected:
                """
                20
                [10]
                10
                []
                -1
                []
                """ + "\n"
        )
    }
}

