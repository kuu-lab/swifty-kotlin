@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenExecutesSequenceMutableConversions() throws {
        let source = """
        fun main() {
            val mutableList = sequenceOf(3, 1, 2, 1, 3).toMutableList()
            mutableList.add(99)
            println(mutableList)

            val mutableSet = sequenceOf(3, 1, 2, 1, 3).toMutableSet()
            mutableSet.add(42)
            println(mutableSet)

            val hashSet = sequenceOf(3, 1, 2, 1, 3).toHashSet()
            hashSet.add(77)
            println(hashSet)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SequenceMutableConversionEdgeCases",
            expected:
                """
                [3, 1, 2, 1, 3, 99]
                [3, 1, 2, 42]
                [3, 1, 2, 77]
                """
                + "\n"
        )
    }
}

