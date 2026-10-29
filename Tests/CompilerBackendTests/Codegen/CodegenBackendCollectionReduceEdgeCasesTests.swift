@testable import CompilerCore
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

    @Test
    func testCodegenIterableReducePrimitiveOperatorCallableReferences() throws {
        let source = """
        fun product(values: List<Long>): Long = values.reduce(Long::times)
        fun iterableProduct(values: Iterable<Long>): Long = values.reduce(Long::times)
        fun iterableSum(values: Iterable<Long>): Long = values.reduce(Long::plus)

        fun main() {
            println(product(listOf(2L, 3L, 4L)))
            println(iterableProduct(listOf(2L, 3L, 4L)))
            println(iterableSum(listOf(2L, 3L, 4L)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IterableReducePrimitiveOperatorCallableReferences",
            expected: "24\n24\n9\n"
        )
    }
}
#endif
