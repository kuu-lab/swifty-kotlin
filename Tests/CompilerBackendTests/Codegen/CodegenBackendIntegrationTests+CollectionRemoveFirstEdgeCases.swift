@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionRemoveFirstMutatesMutableList() throws {
        let source = """
        fun main() {
            val values = mutableListOf(10, 20, 30)
            println(values.removeFirst())
            println(values)
            val typed: MutableList<Int> = mutableListOf(40, 50)
            println(typed.removeFirst())
            println(typed)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRemoveFirstEdgeCases",
            expected:
                """
                10
                [20, 30]
                40
                [50]
                """ + "\n"
        )
    }
}

