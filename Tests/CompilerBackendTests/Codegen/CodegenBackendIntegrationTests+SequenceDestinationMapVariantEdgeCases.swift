@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testSequenceAssociateBuildsMapWithLastWriteWins() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associate { (it % 2) to (it * 10) }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAssociateRuntime", expected: "{1=30, 0=20}\n")
    }

    func testSequenceAssociateByBuildsMapWithLastWriteWins() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associateBy { it % 2 }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAssociateByRuntime", expected: "{1=3, 0=2}\n")
    }

    func testSequenceAssociateToPopulatesMutableMapDestination() throws {
        let source = """
        fun main() {
            val src = sequenceOf("a", "bb", "ccc")
            val dest = mutableMapOf<String, Int>()
            src.associateTo(dest) { it to it.length }
            println(dest["a"])
            println(dest["bb"])
            println(dest["ccc"])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAssociateToRuntime",
            expected:
                """
                1
                2
                3
                """ + "\n"
        )
    }

    func testSequenceAssociateByToMapsKeysToOriginalElements() throws {
        let source = """
        fun main() {
            val src = sequenceOf("apple", "banana", "pear")
            val dest = mutableMapOf<Int, String>()
            src.associateByTo(dest) { it.length }
            println(dest[5])
            println(dest[6])
            println(dest[4])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAssociateByToRuntime",
            expected:
                """
                apple
                banana
                pear
                """ + "\n"
        )
    }

    func testSequenceAssociateWithToUsesElementsAsKeys() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3)
            val dest = mutableMapOf<Int, Int>()
            src.associateWithTo(dest) { it * it }
            println(dest[1])
            println(dest[2])
            println(dest[3])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAssociateWithToRuntime",
            expected:
                """
                1
                4
                9
                """ + "\n"
        )
    }

    func testSequenceGroupByToAppendsIntoMutableListBuckets() throws {
        let source = """
        fun main() {
            val src = sequenceOf(1, 2, 3, 4, 5)
            val dest = mutableMapOf<String, MutableList<Int>>()
            src.groupByTo(dest) { if (it % 2 == 0) "even" else "odd" }
            println(dest["even"])
            println(dest["odd"])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceGroupByToRuntime",
            expected:
                """
                [2, 4]
                [1, 3, 5]
                """ + "\n"
        )
    }
}

