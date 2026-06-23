@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testMeasureTimeMicrosReturnsNonNegativeLong() throws {
        let source = """
        import kotlin.system.measureTimeMicros

        fun main() {
            val elapsed = measureTimeMicros {
                var sum = 0L
                for (i in 1..100) sum += i
            }
            println(elapsed >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureTimeMicrosNonNegative", expected: "true\n")
    }

    func testMeasureTimeMicrosBlockBodyExecutes() throws {
        let source = """
        import kotlin.system.measureTimeMicros

        fun main() {
            var executed = false
            val elapsed = measureTimeMicros {
                executed = true
            }
            println(executed)
            println(elapsed >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureTimeMicrosBlockExecutes", expected: "true\ntrue\n")
    }

    func testMeasureTimeMicrosSideEffectsAreVisible() throws {
        let source = """
        import kotlin.system.measureTimeMicros

        fun main() {
            var counter = 0
            measureTimeMicros {
                counter += 1
                counter += 1
                counter += 1
            }
            println(counter)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureTimeMicrosSideEffects", expected: "3\n")
    }

    func testMeasureTimeMicrosNestedCalls() throws {
        let source = """
        import kotlin.system.measureTimeMicros

        fun main() {
            val outer = measureTimeMicros {
                val inner = measureTimeMicros {
                    var x = 0
                    for (i in 1..10) x += i
                }
                println(inner >= 0)
            }
            println(outer >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureTimeMicrosNested", expected: "true\ntrue\n")
    }
}

