@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCustomCollectionIsEmptyTests {
    @Test
    func testCodegenCustomAbstractCollectionIsEmptyUsesItableDispatch() throws {
        let source = """
        class CustomCollection : AbstractCollection<String?>() {
            override val size: Int get() = 1
            override fun iterator(): Iterator<String?> = emptyList<String?>().iterator()
        }

        fun collectionIsEmpty(value: Collection<String?>): Boolean = value.isEmpty()

        fun main() {
            println(collectionIsEmpty(CustomCollection()))
        }
        """

        try assertKotlinOutput(source, moduleName: "CustomCollectionIsEmpty", expected: "false\n")
    }
}
#endif
