@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testGetTimeNanosReturnsPositiveLong() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main() {
            val t = getTimeNanos()
            println(t > 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeNanosPositive", expected: "true\n")
    }

    func testGetTimeNanosSuccessiveCallsNonDecreasing() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main() {
            val t1 = getTimeNanos()
            val t2 = getTimeNanos()
            println(t2 >= t1)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeNanosNonDecreasing", expected: "true\n")
    }

    func testGetTimeNanosCanMeasureElapsedTime() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main() {
            val before = getTimeNanos()
            var sum = 0L
            for (i in 1..1000) sum += i
            val after = getTimeNanos()
            println(after >= before)
            println(sum == 500500L)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeNanosElapsed", expected: "true\ntrue\n")
    }
}

