@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRunningFoldIndexedUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.runningFoldIndexed(10) { index, acc, value -> acc + index + value })
            println(listOf<Int>().runningFoldIndexed(7) { index, acc, value -> acc + index + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRunningFoldIndexedEdgeCases",
            expected:
                """
                [10, 11, 14, 19]
                [7]
                """ + "\n"
        )
    }
}

