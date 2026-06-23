@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionOrEmptyHandlesNullableListAndMapReceivers() throws {
        let source = """
        fun main() {
            val missingList: List<Int>? = null
            val presentList: List<Int>? = listOf(1, 2, 3)
            val missingMap: Map<String, Int>? = null
            val presentMap: Map<String, Int>? = mapOf("a" to 1, "b" to 2)

            println(missingList.orEmpty())
            println(presentList.orEmpty())
            println(missingMap.orEmpty().count())
            println(presentMap.orEmpty().count())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionOrEmptyEdgeCases", expected: "[]\n[1, 2, 3]\n0\n2\n")
    }
}

