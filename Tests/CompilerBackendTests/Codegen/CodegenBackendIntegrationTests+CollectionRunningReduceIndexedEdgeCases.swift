@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRunningReduceIndexedUsesListRuntimeForParameterReceiver() throws {
        let source = """
        fun printReductions(values: List<Int>) {
            println(values.runningReduceIndexed { index, acc, value -> acc + index + value })
        }

        fun main() {
            printReductions(listOf(1, 2, 3))
            println(listOf<Int>().runningReduceIndexed { index, acc, value -> acc + index + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRunningReduceIndexedEdgeCases",
            expected:
                """
                [1, 4, 9]
                []
                """ + "\n"
        )
    }
}

