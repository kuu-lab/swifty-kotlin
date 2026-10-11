@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionSingleTests {

    @Test
    func testCodegenListSingleUsesRuntimeHelper() throws {
        let source = """
        fun printSingle(values: List<Int>) {
            println(values.single())
        }

        fun main() {
            printSingle(listOf(42))
            println(listOf("only").single())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionSingle", expected: "42\nonly\n")
    }
}
#endif
