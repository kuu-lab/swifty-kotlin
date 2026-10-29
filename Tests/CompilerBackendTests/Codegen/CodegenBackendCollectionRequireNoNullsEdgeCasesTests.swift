@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing


@Suite
struct CodegenBackendCollectionRequireNoNullsEdgeCasesTests {

    @Test
    func codegenCollectionRequireNoNullsChecksIterableReceivers() throws {
        let source = """
        fun main() {
            val values: Iterable<String?> = listOf("a", "b")
            val checked: Iterable<String> = values.requireNoNulls()
            println(checked.toList())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRequireNoNullsEdgeCases",
            expected: "[a, b]\n"
        )
    }

    @Test
    func codegenListRequireNoNullsPreservesListReturnType() throws {
        let source = """
        fun main() {
            val values: List<String?> = listOf("a", "b")
            val checked: List<String> = values.requireNoNulls()
            println(checked)

            try {
                listOf<String?>("a", null).requireNoNulls()
                println("unexpected")
            } catch (e: IllegalArgumentException) {
                println("null")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionRequireNoNullsListReturnType",
            expected: "[a, b]\nnull\n"
        )
    }
}
#endif
