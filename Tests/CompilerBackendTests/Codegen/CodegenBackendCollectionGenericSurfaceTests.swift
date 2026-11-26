@testable import CompilerCore
import Foundation
#if canImport(Testing)
import Testing


@Suite
struct CodegenBackendCollectionGenericSurfaceTests {

    @Test
    func codegenCollectionGenericMembersUseBundledSource() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.any())
            println(collection.all { it > 0 })
            println(collection.last())
            println(collection.toList())
            println(collection.size)
            println(collection.isEmpty())
            println(collection.toTypedArray().size)
            println(collection.toCollection(mutableListOf(0)))

            val iterable: Iterable<String> = setOf("x", "y")
            println(iterable.any { it == "y" })
            println(iterable.last())
            println(iterable.toMutableList().size)

            val set: Collection<String> = setOf("p", "q", "r")
            println(set.size)
            println(set.joinToString(prefix = "<", postfix = ">"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionGenericSurface",
            expected: """
            true
            true
            3
            [1, 2, 3]
            3
            false
            3
            [0, 1, 2, 3]
            true
            y
            2
            3
            <p, q, r>

            """
        )
    }
}
#endif
