@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRequireNoNullsChecksIterableReceivers() throws {
        let source = """
        fun main() {
            val values: Iterable<String?> = listOf("a", "b")
            val checked: Iterable<String> = values.requireNoNulls()
            println(checked.toList())
            println(listOf("x", null).requireNoNulls())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRequireNoNullsEdgeCases",
            expected:
                    """
                    [a, b]
                    """ + "\n"
        )
    }
}

