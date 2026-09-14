@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionLastOrNullTests {

    @Test
    func codegenListLastOrNullUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val ints = listOf(1, 2, 3)
            println(ints.lastOrNull() ?: -1)

            val emptyInts = emptyList<Int>()
            println(emptyInts.lastOrNull() ?: -1)

            val words = listOf("alpha", "beta")
            println(words.lastOrNull() ?: "missing")

            val emptyWords = emptyList<String>()
            println(emptyWords.lastOrNull() ?: "missing")
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionLastOrNull", expected: "3\n-1\nbeta\nmissing\n")
    }
}
#endif
