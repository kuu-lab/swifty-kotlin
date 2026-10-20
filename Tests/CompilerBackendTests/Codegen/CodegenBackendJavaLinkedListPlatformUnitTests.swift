#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendJavaLinkedListPlatformUnitTests {
    @Test
    func propertyReadsPreserveNullFromJavaPlatformUnit() throws {
        let source = """
        import java.util.LinkedList

        class UnitHolder(val values: LinkedList<Unit>) {
            val stored: Unit = values.peekLast()
            val explicit: Unit get() = values.peekLast()
            val block: Unit get() { return values.peekLast() }
        }

        fun main() {
            val holder = UnitHolder(LinkedList<Unit>())
            println(holder?.stored)
            println(holder?.explicit)
            println(holder?.block)
        }
        """

        try assertKotlinOutput(source, moduleName: "JavaLinkedListPlatformUnitProperties", expected: "null\nnull\nnull\n")
    }
}
#endif
