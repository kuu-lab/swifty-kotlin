@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testGetTimeMillisReturnsPositiveLong() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val t = getTimeMillis()
            println(t > 0)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeMillisPositive", expected: "true\n")
    }

    func testGetTimeMillisIsInReasonableEpochRange() throws {
        // 2017-01-01 00:00:00 UTC = 1_483_228_800_000 ms
        // 2049-01-01 00:00:00 UTC = 2_493_072_000_000 ms
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val t = getTimeMillis()
            println(t > 1_483_228_800_000L)
            println(t < 2_493_072_000_000L)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeMillisEpochRange", expected: "true\ntrue\n")
    }

    func testGetTimeMillisSuccessiveCallsNonDecreasing() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val t1 = getTimeMillis()
            val t2 = getTimeMillis()
            println(t2 >= t1)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeMillisNonDecreasing", expected: "true\n")
    }

    func testGetTimeMillisCanMeasureElapsedTime() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val before = getTimeMillis()
            var sum = 0L
            for (i in 1..1000) sum += i
            val after = getTimeMillis()
            println(after >= before)
            println(sum == 500500L)
        }
        """

        try assertKotlinOutput(source, moduleName: "GetTimeMillisElapsed", expected: "true\ntrue\n")
    }
}

