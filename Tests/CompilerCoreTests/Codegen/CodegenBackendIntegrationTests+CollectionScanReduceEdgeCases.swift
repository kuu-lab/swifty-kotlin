@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionScanReduceUsesListRuntimeForParameterReceiver() throws {
        let source = """
        fun printScans(values: List<Int>) {
            println(values.scanReduce { acc, value -> acc + value })
        }

        fun main() {
            printScans(listOf(1, 2, 3))
            println(listOf(4, 5).scanReduce { acc, value -> acc + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionScanReduceEdgeCases",
            expected:
                """
                [1, 3, 6]
                [4, 9]
                """ + "\n"
        )
    }
}

