@testable import CompilerCore
import Foundation

#if canImport(Testing)
import Testing

@Suite(.serialized)
struct CodegenBackendMutableListSortTests {
    @Test
    func testCodegenMutableListSortMutatesPrimitiveAndObjectListsInPlace() throws {
        let source = """
        fun main() {
            val ints = mutableListOf(5, 3, 8, 1, 4)
            ints.sort()
            println(ints)

            val strings = mutableListOf("b", "a", "c")
            strings.sort()
            println(strings)
        }
        """

        try assertKotlinOutput(source, moduleName: "MutableListSortRuntime", expected: "[1, 3, 4, 5, 8]\n[a, b, c]\n")
    }

    @Test
    func testReifiedInlineGenericSortOnLocallyCreatedMutableList() throws {
        let source = """
        inline fun <reified T : Comparable<T>> sortThree(x: T, y: T, z: T): Triple<T, T, T> {
            val values = mutableListOf(x, y, z)
            values.sort()
            return Triple(values[0], values[1], values[2])
        }

        fun main() {
            println(sortThree(3, 1, 2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ReifiedInlineGenericMutableListSort",
            expected: "(1, 2, 3)\n"
        )
    }

}
#endif
