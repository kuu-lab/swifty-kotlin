@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite(.serialized)
struct CodegenBackendCollectionWindowedEdgeCasesTests {

    @Test
    func testCodegenCompilesCollectionWindowedTransformEdgeCases() throws {
        let source = """
        fun main() {
            val numbers: Iterable<Int> = listOf(1, 2, 3, 4, 5)

            val defaultStep = numbers.windowed(3) { window ->
                window.sum()
            }
            println(defaultStep)

            val explicitStep = numbers.windowed(3, 2) { window ->
                window.sum()
            }
            println(explicitStep)

            val partialWindows = numbers.windowed(3, 2, true) { window ->
                window.sum()
            }
            println(partialWindows)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionWindowedEdgeCases",
            expected:
                """
                [6, 9, 12]
                [6, 12]
                [6, 12, 5]
                """ + "\n"
        )
    }

    @Test
    func testCodegenCollectionChunkedEdgeCases() throws {
        let source = """
        fun main() {
            val numbers = listOf(1, 2, 3, 4, 5)
            println(numbers.chunked(2))
            println(numbers.chunked(3) { chunk ->
                chunk.sum()
            })
            println(emptyList<Int>().chunked(2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CollectionChunkedEdgeCases",
            expected:
                """
                [[1, 2], [3, 4], [5]]
                [6, 9]
                []
                """ + "\n"
        )
    }

    @Test
    func testCodegenCollectionChunkedRejectsNonPositiveSizes() throws {
        let source = try diffCaseSource("list_chunked_invalid_size.kt")

        try assertKotlinOutput(
            source,
            moduleName: "ListChunkedInvalidSize",
            expected:
                """
                list-zero:ok
                list-negative:ok
                iterable-zero:ok
                iterable-negative:ok
                array-iterable-zero:ok
                array-iterable-negative:ok
                transform-zero:ok
                transform-negative:ok
                """ + "\n"
        )
    }

    @Test
    func testCodegenConcreteArrayChunkedRejectsNonPositiveSizes() throws {
        let source = """
        fun main() {
            val array = arrayOf(1, 2, 3)
            try {
                array.chunked(0)
                println("array-zero:missing")
            } catch (e: IllegalArgumentException) {
                println("array-zero:ok")
            }
            try {
                array.chunked(-2)
                println("array-negative:missing")
            } catch (e: IllegalArgumentException) {
                println("array-negative:ok")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ConcreteArrayChunkedInvalidSize",
            expected:
                """
                array-zero:ok
                array-negative:ok
                """ + "\n"
        )
    }
}
#endif
