@testable import CompilerCore
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionZipTransformNonLocalReturnTests {

    @Test
    func testIterableZipTransformPreservesNonLocalReturn() throws {
        let source = """
        private fun returnFromZip(values: List<Int>): Int {
            values.zip(listOf(7, 8, 9)) { value, _ ->
                if (value == 2) return 36
                value
            }
            return 0
        }

        fun main() {
            println(returnFromZip(listOf(1, 2, 3)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionZipTransformNonLocalReturn",
            expected: "36\n"
        )
    }
}
#endif
