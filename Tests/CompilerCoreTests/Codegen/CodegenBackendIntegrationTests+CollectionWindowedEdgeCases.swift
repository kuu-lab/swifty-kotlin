@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCollectionFirstNotNullOfUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/collection_firstnotnullof.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

    func testCodegenCollectionFirstNotNullOfOrNullUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/collection_firstnotnullofornull.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

    func testCodegenCollectionMinusElementUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/collection_minuselement.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

    func testCodegenCollectionReduceRightIndexedUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/collection_reducerightindexed.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

    func testCodegenCollectionReduceRightIndexedOrNullUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/collection_reducerightindexedornull.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

    func testCodegenCollectionReduceRightOrNullUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/collection_reducerightornull.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

    func testCodegenCollectionSumByUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/collection_sumby.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

    func testCodegenCollectionSumByDoubleUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/collection_sumbydouble.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

