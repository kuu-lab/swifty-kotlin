@testable import CompilerCore
import Foundation
import XCTest

// STDLIB-SYSTEM-FN-006: measureTimeMicros end-to-end codegen tests.
//
// measureTimeMicros { block } returns the elapsed microseconds as Long.
// The exact value is non-deterministic (depends on the host clock), so tests
// verify invariants that hold regardless of timing: the result is >= 0 and
// the block body actually executes.

extension CodegenBackendIntegrationTests {

    // MARK: - Basic usage: result is non-negative

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureTimeMicrosNonNegative",
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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureTimeMicrosBlockExecutes",
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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureTimeMicrosSideEffects",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\n")
        }
    }

    // MARK: - Nested measureTimeMicros calls

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureTimeMicrosNested",
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
