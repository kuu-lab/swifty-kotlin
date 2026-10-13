@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionLastIndexOfTests {

    @Test
    func testCodegenListLastIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val ints: List<Int> = listOf(1, 2, 3, 2)
            println(ints.lastIndexOf(2))
            println(ints.lastIndexOf(4))

            val words: List<String> = listOf("alpha", "beta", "alpha")
            println(words.lastIndexOf("alpha"))
            println(words.lastIndexOf("gamma"))
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionLastIndexOf", expected: "3\n-1\n2\n-1\n")
    }
}
#endif
