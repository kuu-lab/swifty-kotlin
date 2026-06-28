@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesComparableMaxOfEdgeCases() throws {
        let source = """
        fun main() {
            // 2-arg Comparable maxOf
            println(maxOf("banana", "apple"))

            // 3-arg Comparable maxOf
            println(maxOf("cherry", "apple", "banana"))

            // vararg Comparable maxOf (4 args)
            println(maxOf("date", "banana", "apple", "cherry"))

            // vararg with winner at start
            println(maxOf("zebra", "ant", "cat"))

            // vararg with winner at end
            println(maxOf("ant", "cat", "zebra"))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparableMaxOfEdgeCases",
            expected:
                """
                banana
                cherry
                date
                zebra
                zebra

                """
        )
    }
}

