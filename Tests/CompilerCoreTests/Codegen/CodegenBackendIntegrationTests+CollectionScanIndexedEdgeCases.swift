@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionScanIndexedUsesListRuntime() throws {
        let source = """
        fun main() {
            val empty = listOf<Int>().scanIndexed(100) { index, acc, value -> acc + index + value }
            println(empty)

            val single = listOf(5).scanIndexed(100) { index, acc, value -> acc + index + value }
            println(single)

            val multi = listOf(1, 2, 3).scanIndexed(0) { index, acc, value -> acc + value * index }
            println(multi)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionScanIndexedEdgeCases",
            expected:
                """
                [100]
                [100, 105]
                [0, 0, 2, 8]
                """ + "\n"
        )
    }
}

