@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRunningFoldUsesListRuntime() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            println(values.runningFold(10) { acc, value -> acc + value })
            println(listOf<Int>().runningFold(7) { acc, value -> acc + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRunningFoldEdgeCases",
            expected:
                """
                [10, 11, 13, 16]
                [7]
                """ + "\n"
        )
    }
}

