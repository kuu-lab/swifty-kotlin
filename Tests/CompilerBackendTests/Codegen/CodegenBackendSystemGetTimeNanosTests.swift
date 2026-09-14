#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSystemGetTimeNanosTests {

    @Test
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

    @Test
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

    @Test
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
#endif
