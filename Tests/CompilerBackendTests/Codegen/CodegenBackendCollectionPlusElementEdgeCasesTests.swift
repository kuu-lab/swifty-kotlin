@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionPlusElementEdgeCasesTests {

    @Test
    func testCodegenCollectionPlusElementAppendsElementToIterableAsList() throws {
        let source = """
        fun main() {
            println(listOf(1, 2).plusElement(3))
            println(setOf("a", "b").plusElement("c"))
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionPlusElementEdgeCases", expected: "[1, 2, 3]\n[a, b, c]\n")
    }
}
#endif
