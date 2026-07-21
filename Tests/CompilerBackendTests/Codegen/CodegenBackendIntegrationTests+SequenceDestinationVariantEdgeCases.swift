@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testSequenceMapToAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3)
            val dest = mutableListOf("seed")
            val result = src.mapTo(dest) { it.toString() }
            println(result)
            println(dest)
        }
        """
        try assertKotlinOutput(source, moduleName: "STDLIBSEQ022_MAP_TO", expected: "[seed, 1, 2, 3]\n[seed, 1, 2, 3]\n")
    }

    func testSequenceMapNotNullToAppendsNonNullTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3, 4)
            val dest = mutableListOf("seed")
            val result = src.mapNotNullTo(dest) {
                if (it % 2 == 0) it.toString() else null
            }
            println(result)
            println(dest)
        }
        """
        try assertKotlinOutput(source, moduleName: "STDLIBSEQ022_MAP_NOT_NULL_TO", expected: "[seed, 2, 4]\n[seed, 2, 4]\n")
    }

    func testSequenceMapIndexedToAppendsIndexedTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf(10, 20, 30)
            val dest = mutableListOf("seed")
            val result = src.mapIndexedTo(dest) { index, value ->
                index.toString() + ":" + value.toString()
            }
            println(result)
            println(dest)
        }
        """

        try assertKotlinOutput(source, moduleName: "STDLIBSEQ022_MAP_INDEXED_TO", expected: "[seed, 0:10, 1:20, 2:30]\n[seed, 0:10, 1:20, 2:30]\n")
    }

    func testSequenceFlatMapToAppendsFlattenedTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf("a", "bc")
            val dest = mutableListOf("seed")
            val result = src.flatMapTo(dest) { value ->
                listOf(value, value + value)
            }
            println(result)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFlatMapToRuntime",
            expected:
                """
                [seed, a, aa, bc, bcbc]
                """ + "\n"
        )
    }

    func testSequenceMapIndexedNotNullToAppendsNonNullIndexedTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf(10, 20, 30, 40)
            val dest = mutableListOf("seed")
            val result = src.mapIndexedNotNullTo(dest) { index, value ->
                if (index % 2 == 0) index.toString() + ":" + value.toString() else null
            }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinOutput(source, moduleName: "STDLIBSEQ022_02", expected: "true\n[seed, 0:10, 2:30]\n")
    }

    func testSequenceFlatMapIndexedToAppendsFlattenedIndexedTransforms() throws {
        let source = """
        fun main() {
            val src = sequenceOf("a", "bc")
            val dest = mutableListOf("seed")
            val result = src.flatMapIndexedTo(dest) { index, value ->
                listOf(index.toString() + ":" + value, value + value)
            }
            println(result)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceFlatMapIndexedToRuntime",
            expected:
                """
                [seed, 0:a, aa, 1:bc, bcbc]
                """ + "\n"
        )
    }
}

