@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceUnionExecutes() throws {
        let source = """
        fun main() {
            val unioned = sequenceOf(1, 2, 3, 2).union(listOf(3, 4, 1))
            println(unioned)
            println(unioned.size)
            println(unioned.contains(4))
            println(unioned.contains(99))

            println(emptySequence<Int>().union(listOf(5, 5, 6)))
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceUnionRuntime", expected: "[1, 2, 3, 4]\n4\ntrue\nfalse\n[5, 6]\n")
    }
}

