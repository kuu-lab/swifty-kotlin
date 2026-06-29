@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testMeasureNanoTimeReturnsNonNegativeLong() throws {
        let source = """
        import kotlin.system.measureNanoTime

        fun main() {
            val elapsed = measureNanoTime {
                var sum = 0L
                for (i in 1..100) sum += i
            }
            println(elapsed >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureNanoTimeNonNegative", expected: "true\n")
    }

    func testMeasureNanoTimeBlockBodyExecutes() throws {
        let source = """
        import kotlin.system.measureNanoTime

        fun main() {
            var executed = false
            val elapsed = measureNanoTime {
                executed = true
            }
            println(executed)
            println(elapsed >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureNanoTimeBlockExecutes", expected: "true\ntrue\n")
    }

    func testMeasureNanoTimeSideEffectsAreVisible() throws {
        let source = """
        import kotlin.system.measureNanoTime

        fun main() {
            var counter = 0
            measureNanoTime {
                counter += 1
                counter += 1
                counter += 1
            }
            println(counter)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureNanoTimeSideEffects", expected: "3\n")
    }

    func testMeasureNanoTimeNestedCalls() throws {
        let source = """
        import kotlin.system.measureNanoTime

        fun main() {
            val outer = measureNanoTime {
                val inner = measureNanoTime {
                    var x = 0
                    for (i in 1..10) x += i
                }
                println(inner >= 0)
            }
            println(outer >= 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "MeasureNanoTimeNested", expected: "true\ntrue\n")
    }
}

