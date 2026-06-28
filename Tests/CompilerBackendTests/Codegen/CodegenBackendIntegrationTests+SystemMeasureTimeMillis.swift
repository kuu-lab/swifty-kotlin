@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testMeasureTimeMillisReturnsNonNegativeLong() throws {
        let source = """
        import kotlin.system.measureTimeMillis

        fun main() {
            val elapsed = measureTimeMillis {
                var sum = 0L
                for (i in 1..100) sum += i
            }
            println(elapsed >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureTimeMillisNonNegative", expected: "true\n")
    }

    func testMeasureTimeMillisBlockBodyExecutes() throws {
        let source = """
        import kotlin.system.measureTimeMillis

        fun main() {
            var executed = false
            val elapsed = measureTimeMillis {
                executed = true
            }
            println(executed)
            println(elapsed >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureTimeMillisBlockExecutes", expected: "true\ntrue\n")
    }

    func testMeasureTimeMillisSideEffectsAreVisible() throws {
        let source = """
        import kotlin.system.measureTimeMillis

        fun main() {
            var counter = 0
            measureTimeMillis {
                counter += 1
                counter += 1
                counter += 1
            }
            println(counter)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureTimeMillisSideEffects", expected: "3\n")
    }

    func testMeasureTimeMillisNestedCalls() throws {
        let source = """
        import kotlin.system.measureTimeMillis

        fun main() {
            val outer = measureTimeMillis {
                val inner = measureTimeMillis {
                    var x = 0
                    for (i in 1..10) x += i
                }
                println(inner >= 0)
            }
            println(outer >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureTimeMillisNested", expected: "true\ntrue\n")
    }
}

