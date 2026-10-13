#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendCollectionReduceRightEdgeCasesTests {

    @Test
    func testCodegenCollectionReduceRightReadsIterableReceivers() throws {
        let source = """
        fun main() {
            println(setOf(1, 2, 3).reduceRight { value, acc -> value - value + acc - acc + 7 })
            val values: Iterable<Int> = setOf(4, 5, 6)
            println(values.reduceRight { value, acc -> value - value + acc - acc + 7 })
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionReduceRightEdgeCases", expected: "7\n7\n")
    }
}
#endif
