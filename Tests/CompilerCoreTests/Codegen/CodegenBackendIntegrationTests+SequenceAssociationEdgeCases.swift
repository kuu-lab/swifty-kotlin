@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testSequenceAssociateBuildsMapWithUniqueKeys() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associate { it to it * 10 }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAssociateUniqueKeys", expected: "{1=10, 2=20, 3=30}\n")
    }

    func testSequenceAssociateEmptySequenceReturnsEmptyMap() throws {
        let source = """
        fun main() {
            val result = emptySequence<Int>().associate { it to it * 10 }
            println(result)
            println(result.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAssociateEmptySeq", expected: "{}\n0\n")
    }

    func testSequenceAssociateWithStringElementsProducesStringIntMap() throws {
        let source = """
        fun main() {
            val result = sequenceOf("a", "bb", "ccc").associate { it to it.length }
            println(result["a"])
            println(result["bb"])
            println(result["ccc"])
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceAssociateStringKeys", expected: "1\n2\n3\n")
    }

    func testSequenceAssociateAllowsKeyLookupInResult() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associate { it to it * it }
            println(result[1])
            println(result[2])
            println(result[3])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAssociateKeyLookup",
            expected:
                """
                1
                4
                9
                """ + "\n"
        )
    }

    func testSequenceAssociateWithMapsElementsToTransformedValues() throws {
        let source = """
        fun main() {
            val result = sequenceOf(1, 2, 3).associateWith { value ->
                value * value
            }
            println(result[1])
            println(result[2])
            println(result[3])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceAssociateWithRuntime",
            expected:
                """
                1
                4
                9
                """ + "\n"
        )
    }
}

