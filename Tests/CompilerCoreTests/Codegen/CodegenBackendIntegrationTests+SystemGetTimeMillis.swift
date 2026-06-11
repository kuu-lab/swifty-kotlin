@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-SYSTEM-FN-003: getTimeMillis end-to-end codegen tests.
//
// kotlin.system.getTimeMillis() returns the current wall-clock time in
// milliseconds since the Unix epoch (same semantics as System.currentTimeMillis).
// Results are non-deterministic, so tests verify invariants that hold regardless
// of when they run: the value is positive, within a reasonable epoch range, and
// successive calls are non-decreasing.

extension CodegenBackendIntegrationTests {

    // MARK: - Basic usage: result is positive

    func testGetTimeMillisReturnsPositiveLong() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val t = getTimeMillis()
            println(t > 0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GetTimeMillisPositive",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\n")
        }
    }

    // MARK: - Epoch range sanity check

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GetTimeMillisEpochRange",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\n")
        }
    }

    // MARK: - Successive calls are non-decreasing

    func testGetTimeMillisSuccessiveCallsNonDecreasing() throws {
        let source = """
        import kotlin.system.getTimeMillis

        fun main() {
            val t1 = getTimeMillis()
            val t2 = getTimeMillis()
            println(t2 >= t1)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GetTimeMillisNonDecreasing",
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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "GetTimeMillisElapsed",
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
