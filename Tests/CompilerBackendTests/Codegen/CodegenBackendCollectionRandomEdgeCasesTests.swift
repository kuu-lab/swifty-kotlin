@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionRandomEdgeCasesTests {

    @Test
    func codegenCollectionRandomReadsCollectionReceivers() throws {
        let source = """
        fun main() {
            println(setOf("solo").random())
            val values: Collection<Int> = setOf(7)
            println(values.random())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionRandomEdgeCases", expected: "solo\n7\n")
    }
}
#endif
