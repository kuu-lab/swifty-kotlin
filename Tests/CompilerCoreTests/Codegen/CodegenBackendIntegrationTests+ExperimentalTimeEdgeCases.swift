@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesTestTimeSource() throws {
        let source = """
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.nanoseconds
        import kotlin.time.ExperimentalTime
        import kotlin.time.TestTimeSource

        @OptIn(ExperimentalTime::class)
        fun main() {
            val source = TestTimeSource()
            val mark1 = source.markNow()

            source += 5.milliseconds
            val mark2 = source.markNow()

            source += 10.milliseconds
            val mark3 = source.markNow()

            // mark differences are deterministic
            println((mark2 - mark1).inWholeMilliseconds)
            println((mark3 - mark2).inWholeMilliseconds)
            println((mark3 - mark1).inWholeMilliseconds)

            // mark ordering is deterministic
            println(mark1.compareTo(mark2) < 0)
            println(mark2.compareTo(mark3) < 0)

            // advancing by nanoseconds
            source += 500.nanoseconds
            val mark4 = source.markNow()
            println((mark4 - mark3).inWholeNanoseconds)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "TestTimeSourceEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                5
                10
                15
                true
                true
                500
                """
                + "\n"
            )
        }
    }

    func testCodegenCompilesExperimentalTimeEdgeCases() throws {
        let source = """
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.ExperimentalTime
        import kotlin.time.*

        @OptIn(ExperimentalTime::class)
        fun main() {
            val start = TimeSource.Monotonic.markNow()
            val future = start + 5.milliseconds
            val past = future - 10.milliseconds

            println((future - start).inWholeMilliseconds)
            println((future - past).inWholeMilliseconds)
            // hasNotPassedNow() is timing-sensitive; only check past.hasPassedNow()
            println(past.hasPassedNow())
            val clock = TimeSource.Monotonic.asClock(Instant.fromEpochMilliseconds(0L))
            println(clock.now().epochSeconds >= 0L)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ExperimentalTimeEdgeCases",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                5
                10
                true
                true
                """
                + "\n"
            )
        }
    }
}
