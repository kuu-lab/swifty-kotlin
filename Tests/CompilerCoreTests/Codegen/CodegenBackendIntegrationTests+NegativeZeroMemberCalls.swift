@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testNegativeZeroDoubleToString() throws {
        let source = """
        fun main() {
            println((-0.0).toString())
            val z: Double = -0.0
            println(z.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "NegZeroDoubleToString", expected: "-0.0\n-0.0\n")
    }

    func testNegativeZeroFloatToString() throws {
        let source = """
        fun main() {
            println((-0.0f).toString())
            val z: Float = -0.0f
            println(z.toString())
        }
        """
        try assertKotlinOutput(source, moduleName: "NegZeroFloatToString", expected: "-0.0\n-0.0\n")
    }

    func testNegativeZeroReturnValue() throws {
        let source = """
        fun negZeroDouble(): Double = -0.0
        fun negZeroFloat(): Float = -0.0f
        fun main() {
            println(negZeroDouble())
            println(negZeroFloat())
        }
        """
        try assertKotlinOutput(source, moduleName: "NegZeroReturnValue", expected: "-0.0\n-0.0\n")
    }
}

