#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct CodegenBackendListSortedByTests {

    @Test
    func testCodegenListSortedByUsesPrimitiveAndObjectSelectorPaths() throws {
        let source = """
        fun main() {
            println(listOf(22, 12, 21, 11).sortedBy { it % 10 })
            println(listOf("b", "a", "c").sortedBy { it })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListSortedByRuntime", expected: "[21, 11, 22, 12]\n[a, b, c]\n")
    }
}
#endif
