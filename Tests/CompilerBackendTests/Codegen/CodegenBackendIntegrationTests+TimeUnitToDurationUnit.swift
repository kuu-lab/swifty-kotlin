// STDLIB-TIME-FN-006: End-to-end execution tests for TimeUnit.toDurationUnit().
// kk_time_unit_to_duration_unit maps a java.util.concurrent.TimeUnit ordinal to the
// matching kotlin.time.DurationUnit ordinal. Synthetic enums have no $enumOrdinalToName
// helper, so println prints the DurationUnit ordinal integer.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

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

        try assertKotlinOutput(
            source,
            moduleName: "TimeUnitToDurationUnitOrdinals",
            expected:
                """
                0
                1
                2
                3
                4
                5
                6
                """
                + "\n"
        )
    }

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

        try assertKotlinOutput(source, moduleName: "TimeUnitToDurationUnitFeedsToDuration", expected: "2\n500\n")
    }
}

