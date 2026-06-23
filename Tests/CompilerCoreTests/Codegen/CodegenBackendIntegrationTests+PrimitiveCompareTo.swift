@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesPrimitiveCompareTo() throws {
        let source = """
        fun main() {
            // Int — direct member call
            println(10.compareTo(20))
            println(20.compareTo(10))
            println(7.compareTo(7))
            // Int — inside a (Int, Int) -> Int lambda
            val cmpInt: (Int, Int) -> Int = { x, y -> x.compareTo(y) }
            println(cmpInt(30, 5))
            // Long
            println(100L.compareTo(200L))
            // Double — direct and inside a (Double, Double) -> Int lambda
            println(2.5.compareTo(1.5))
            val cmpDouble: (Double, Double) -> Int = { x, y -> x.compareTo(y) }
            println(cmpDouble(1.0, 9.0))
            // Float — direct and inside a (Float, Float) -> Int lambda
            println(2.5f.compareTo(1.5f))
            val cmpFloat: (Float, Float) -> Int = { x, y -> x.compareTo(y) }
            println(cmpFloat(1.0f, 9.0f))
            // Boolean (false < true)
            println(false.compareTo(true))
        }
        """
        try assertKotlinOutput(source, moduleName: "PrimitiveCompareTo", expected: "-1\n1\n0\n1\n-1\n1\n-1\n1\n-1\n-1\n")
    }
}

