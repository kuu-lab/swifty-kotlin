@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionScanUsesListRuntimeForParameterReceiver() throws {
        let source = """
        fun printScans(values: List<Int>) {
            println(values.scan(10) { acc, value -> acc + value })
        }

        fun main() {
            printScans(listOf(1, 2, 3))
            println(listOf<Int>().scan(7) { acc, value -> acc + value })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionScanEdgeCases",
            expected:
                """
                [10, 11, 13, 16]
                [7]
                """ + "\n"
        )
    }
}

