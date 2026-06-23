@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveLastMutatesMutableList() throws {
        let source = """
        fun main() {
            val values = mutableListOf(10, 20, 30)
            println(values.removeLast())
            println(values)
            val typed: MutableList<Int> = mutableListOf(40, 50)
            println(typed.removeLast())
            println(typed)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRemoveLastEdgeCases",
            expected:
                """
                30
                [10, 20]
                50
                [40]
                """ + "\n"
        )
    }
}

