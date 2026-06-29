@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionPlusAssignMutatesMutableCollections() throws {
        let source = """
        fun main() {
            val list = mutableListOf(1)
            list += 2
            list += listOf(3, 4)
            println(list)

            val set = mutableSetOf("a")
            set += "b"
            set += setOf("b", "c")
            println(set)

            val map = mutableMapOf("a" to 1)
            map += ("b" to 2)
            map += mapOf("a" to 9, "c" to 3)
            println(map)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionPlusAssignEdgeCases", expected: "[1, 2, 3, 4]\n[a, b, c]\n{a=9, b=2, c=3}\n")
    }
}

