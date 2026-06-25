@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// STDLIB-SYSTEM-FN-005: measureNanoTime end-to-end codegen tests.
//
// measureNanoTime { block } returns the elapsed nanoseconds as Long.
// The exact value is non-deterministic (depends on the host clock), so tests
// verify invariants that hold regardless of timing: the result is >= 0 and
// the block body actually executes.

extension CodegenBackendIntegrationTests {

    // MARK: - Basic usage: result is non-negative

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureNanoTimeNonNegative",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\n")
        }
    }

    // MARK: - Block body executes

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureNanoTimeBlockExecutes",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\n")
        }
    }

    // MARK: - Side effects inside block are visible after call

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureNanoTimeSideEffects",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\n")
        }
    }

    // MARK: - Nested measureNanoTime calls

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureNanoTimeNested",
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
