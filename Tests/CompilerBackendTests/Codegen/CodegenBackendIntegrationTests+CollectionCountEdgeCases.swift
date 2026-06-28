@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionCountEdgeCases() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4)
            println(values.count())
            println(values.count { it % 2 == 0 })

            val array = arrayOf(1, 2, 3, 4)
            println(array.count())
            println(array.count { it > 2 })

            val map = mapOf("a" to 1, "b" to 2, "c" to 3)
            println(map.count())
            println(map.count { it.value >= 2 })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionCountEdgeCases", expected: "4\n2\n4\n2\n3\n2\n")
    }
}

