@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite(.serialized)
struct CodegenBackendCollectionWindowedEdgeCasesTests {

    @Test
    func testCodegenCollectionFirstNotNullOfUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("collection_firstnotnullof.kt")

        try assertKotlinOutput(
            source,
            moduleName: "CollectionFirstNotNullOf",
            expected:
                """
                two
                missing
                """ + "\n"
        )
    }

    @Test
    func testCodegenCollectionFirstNotNullOfOrNullUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("collection_firstnotnullofornull.kt")

        try assertKotlinOutput(
            source,
            moduleName: "CollectionFirstNotNullOfOrNull",
            expected:
                """
                two
                missing
                """ + "\n"
        )
    }

    @Test
    func testCodegenCollectionMinusElementUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("collection_minuselement.kt")

        try assertKotlinOutput(
            source,
            moduleName: "CollectionMinusElement",
            expected:
                """
                [1, 2, 3]
                [1, 2, 2, 3]
                []
                """ + "\n"
        )
    }

    @Test
    func testCodegenCollectionReduceRightIndexedUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("collection_reducerightindexed.kt")

        try assertKotlinOutput(
            source,
            moduleName: "CollectionReduceRightIndexed",
            expected:
                """
                133
                7
                empty
                """ + "\n"
        )
    }

    @Test
    func testCodegenCollectionReduceRightIndexedOrNullUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("collection_reducerightindexedornull.kt")

        try assertKotlinOutput(
            source,
            moduleName: "CollectionReduceRightIndexedOrNull",
            expected:
                """
                133
                7
                -1
                """ + "\n"
        )
    }

    @Test
    func testCodegenCollectionReduceRightOrNullUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("collection_reducerightornull.kt")

        try assertKotlinOutput(
            source,
            moduleName: "CollectionReduceRightOrNull",
            expected:
                """
                33
                7
                -1
                """ + "\n"
        )
    }

    @Test
    func testCodegenCollectionSumByUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("collection_sumby.kt")

        try assertKotlinOutput(
            source,
            moduleName: "CollectionSumBy",
            expected:
                """
                14
                21
                0
                """ + "\n"
        )
    }

    @Test
    func testCodegenCollectionSumByDoubleUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("collection_sumbydouble.kt")

        try assertKotlinOutput(
            source,
            moduleName: "CollectionSumByDouble",
            expected:
                """
                2.0
                7.5
                0.0
                """ + "\n"
        )
    }

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
}
#endif
