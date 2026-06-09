// STDLIB-TIME-FN-006: End-to-end execution tests for TimeUnit.toDurationUnit().
// kk_time_unit_to_duration_unit maps a java.util.concurrent.TimeUnit ordinal to the
// matching kotlin.time.DurationUnit ordinal. Synthetic enums have no $enumOrdinalToName
// helper, so println prints the DurationUnit ordinal integer.
@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    // MARK: - TimeUnit.toDurationUnit() ordinals

    func testCodegenTimeUnitToDurationUnitOrdinals() throws {
        let source = """
        import java.util.concurrent.TimeUnit
        import kotlin.time.toDurationUnit

        fun main() {
            println(TimeUnit.NANOSECONDS.toDurationUnit())
            println(TimeUnit.MICROSECONDS.toDurationUnit())
            println(TimeUnit.MILLISECONDS.toDurationUnit())
            println(TimeUnit.SECONDS.toDurationUnit())
            println(TimeUnit.MINUTES.toDurationUnit())
            println(TimeUnit.HOURS.toDurationUnit())
            println(TimeUnit.DAYS.toDurationUnit())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "TimeUnitToDurationUnitOrdinals",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                0
                1
                2
                3
                4
                5
                6
                """
                + "\n",
                "TimeUnit and DurationUnit share entry ordering, so each ordinal maps to itself"
            )
        }
    }

    // MARK: - Returned DurationUnit feeds back into toDuration

    func testCodegenTimeUnitToDurationUnitFeedsToDuration() throws {
        let source = """
        import java.util.concurrent.TimeUnit
        import kotlin.time.toDurationUnit
        import kotlin.time.toDuration

        fun main() {
            val unit = TimeUnit.SECONDS.toDurationUnit()
            println(2.toDuration(unit).inWholeSeconds)
            println(500L.toDuration(TimeUnit.MILLISECONDS.toDurationUnit()).inWholeMilliseconds)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "TimeUnitToDurationUnitFeedsToDuration",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "2\n500\n", "Converted DurationUnit must drive toDuration scaling")
        }
    }
}
