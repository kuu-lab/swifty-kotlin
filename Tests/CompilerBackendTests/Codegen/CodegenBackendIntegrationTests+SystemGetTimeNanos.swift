@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// STDLIB-SYSTEM-FN-004: getTimeNanos end-to-end codegen tests.
//
// kotlin.system.getTimeNanos() returns a monotonic nanosecond timestamp as Long.
// The exact value is host-dependent, so these tests verify stable invariants:
// the value is positive, successive reads do not go backwards, and elapsed-time
// computations can use it without affecting normal Long arithmetic.

extension CodegenBackendIntegrationTests {

    // MARK: - Basic usage: result is positive

    func testGetTimeNanosReturnsPositiveLong() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main() {
            val t = getTimeNanos()
            println(t > 0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GetTimeNanosPositive",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\n")
        }
    }

    // MARK: - Successive calls are non-decreasing

    func testGetTimeNanosSuccessiveCallsNonDecreasing() throws {
        let source = """
        import kotlin.system.getTimeNanos

        fun main() {
            val t1 = getTimeNanos()
            val t2 = getTimeNanos()
            println(t2 >= t1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GetTimeNanosNonDecreasing",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\n")
        }
    }

    // MARK: - Usable in elapsed-time computation

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GetTimeNanosElapsed",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\n")
        }
    }
}
