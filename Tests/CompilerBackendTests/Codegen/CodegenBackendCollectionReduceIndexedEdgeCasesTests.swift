@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionReduceIndexedEdgeCasesTests {

    @Test
    func testCodegenCollectionReduceIndexedReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceIndexed { index, acc, value -> index + acc - acc + value - value })
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceIndexed { index, acc, value -> index + acc - acc + value - value })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceIndexedEdgeCases", expected: "2\n2\n")
    }

    @Test
    func testCodegenIterableReduceIndexedRetainsCompatibilityBridge() throws {
        let source = """
        fun main() {
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceIndexed { index, acc, value -> index + acc - acc + value - value })
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableReduceIndexedCompatibility", expected: "2\n")
    }
}
#endif
