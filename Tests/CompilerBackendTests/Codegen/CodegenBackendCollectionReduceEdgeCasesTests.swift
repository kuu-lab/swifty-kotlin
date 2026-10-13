@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionReduceEdgeCasesTests {

    @Test
    func testCodegenCollectionReduceReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduce { acc, value -> acc + value })
            val values: Iterable<Int> = setOf(2, 3, 4)
            println(values.reduce { acc, value -> acc * value })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceEdgeCases", expected: "6\n24\n")
    }
}
#endif
