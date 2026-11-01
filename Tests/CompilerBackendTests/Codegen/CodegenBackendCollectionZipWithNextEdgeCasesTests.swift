@testable import CompilerCore
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendCollectionZipWithNextEdgeCasesTests {

    @Test
    func testCodegenCollectionZipWithNextOverloads() throws {
        let source = """
        fun main() {
            val values = listOf(1, 3, 6, 10)
            println(values.zipWithNext())
            println(values.zipWithNext { left, right -> right - left })
            println(listOf(1).zipWithNext())
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionZipWithNextOverloads", expected: "[(1, 3), (3, 6), (6, 10)]\n[2, 3, 4]\n[]\n")
    }

    @Test
    func testCodegenCollectionZipWithNextRangeReceiver() throws {
        // KUU-3978: a RuntimeRangeBox receiver is a valid Iterable source for
        // the generic zipWithNext bridge (previously panicked with
        // "invalid collection handle").
        let source = """
        fun main() {
            println((1..5).zipWithNext())
            println((1..4).zipWithNext { a, b -> a + b })
            println((4 downTo 1).zipWithNext())
            println((1..9 step 3).zipWithNext())
            println((1 until 5).zipWithNext())
            println(('a'..'d').zipWithNext())
            println((1L..4L).zipWithNext())
            println((5..5).zipWithNext())
            println((3..0).zipWithNext())
            println((1..3).zip(listOf("a", "b")))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionZipWithNextRangeReceiver",
            expected: "[(1, 2), (2, 3), (3, 4), (4, 5)]\n[3, 5, 7]\n[(4, 3), (3, 2), (2, 1)]\n[(1, 4), (4, 7)]\n[(1, 2), (2, 3), (3, 4)]\n[(a, b), (b, c), (c, d)]\n[(1, 2), (2, 3), (3, 4)]\n[]\n[]\n[(1, a), (2, b)]\n"
        )
    }

    @Test
    func testCodegenCollectionZipWithNextSupportsNonLocalReturn() throws {
        let source = """
        private fun returnFromZipWithNext(values: List<Int>): Int {
            values.zipWithNext { _, second ->
                if (second == 2) return 37
                second
            }
            return 0
        }

        fun main() {
            println(returnFromZipWithNext(listOf(1, 2, 3)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionZipWithNextNonLocalReturn",
            expected: "37\n"
        )
    }
}
#endif
