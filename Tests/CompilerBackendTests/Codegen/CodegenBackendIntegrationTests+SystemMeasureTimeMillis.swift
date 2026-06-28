@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// STDLIB-SYSTEM-FN-007: measureTimeMillis end-to-end codegen tests.
//
// measureTimeMillis { block } returns elapsed wall-clock milliseconds as Long.
// The exact value is non-deterministic, so tests verify invariants: result >= 0
// and the block body actually executes.

extension CodegenBackendIntegrationTests {

    // MARK: - Basic usage: result is non-negative

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureTimeMillisNonNegative",
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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureTimeMillisBlockExecutes",
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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureTimeMillisSideEffects",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\n")
        }
    }

    // MARK: - Nested measureTimeMillis calls

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

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MeasureTimeMillisNested",
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
