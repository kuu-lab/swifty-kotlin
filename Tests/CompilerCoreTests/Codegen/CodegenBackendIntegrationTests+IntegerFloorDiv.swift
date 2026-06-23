@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesIntegerFloorDivMatrix() throws {
        let source = """
        fun main() {
            println(7.floorDiv(3))
            println((-7).floorDiv(3))
            println(7.floorDiv(-3))
            println((-7).floorDiv(-3))
            println(7L.floorDiv(3))
            println(7.floorDiv(3L))
            println(1.toByte().floorDiv(2.toShort()))
            println(100u.floorDiv(3u))
            println(100uL.floorDiv(3u))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntegerFloorDivMatrix",
            expected:
                """
                2
                -3
                -3
                2
                2
                2
                0
                33
                33
                """ + "\n"
        )
    }
}

