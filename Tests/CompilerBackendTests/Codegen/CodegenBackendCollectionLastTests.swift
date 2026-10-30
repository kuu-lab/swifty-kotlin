@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionLastTests {
    @Test
    func testCodegenIterableLastUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val map = mutableMapOf("k" to 1)
            println(map.values.first())
            println(map.values.last())

            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.last())

            val iterable: Iterable<String> = setOf("x", "y")
            println(iterable.last())
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableLastRuntime", expected: "1\n1\n3\ny\n")
    }
}
#endif
