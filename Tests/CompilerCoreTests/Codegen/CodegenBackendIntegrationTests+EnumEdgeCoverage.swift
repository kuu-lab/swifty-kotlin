@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesEnumEdgeCoverage() throws {
        let source = """
        enum class Direction {
            NORTH,
            SOUTH,
        }

        fun main() {
            println(Direction.entries)
            println(enumValues<Direction>().toList())
            println(enumValueOf<Direction>("NORTH"))
            println(Direction.SOUTH.name)
            println(Direction.SOUTH.ordinal)

            try {
                println(enumValueOf<Direction>("WEST"))
            } catch (e: Throwable) {
                println("invalid-enum-name")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "EnumEdgeCoverage",
            expected:
                """
                [NORTH, SOUTH]
                [NORTH, SOUTH]
                NORTH
                SOUTH
                1
                invalid-enum-name
                """
                + "\n"
        )
    }
}

