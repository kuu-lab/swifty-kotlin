@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionZipWithNextOverloads() throws {
        let source = """
        fun main() {
            val values = listOf(1, 3, 6, 10)
            println(values.zipWithNext())
            println(values.zipWithNext { left, right -> right - left })
            println(listOf(1).zipWithNext())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionZipWithNextOverloads", expected: "[(1, 3), (3, 6), (6, 10)]\n[2, 3, 4]\n[]\n")
    }
}

