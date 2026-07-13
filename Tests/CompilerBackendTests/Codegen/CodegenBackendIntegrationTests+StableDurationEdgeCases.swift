@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testDurationStableUnitExtensionPropertiesInt() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.microseconds
        import kotlin.time.Duration.Companion.nanoseconds
        import kotlin.time.Duration.Companion.minutes
        import kotlin.time.Duration.Companion.hours
        import kotlin.time.Duration.Companion.days

        fun main() {
            println(1.seconds.inWholeSeconds)
            println(1500.milliseconds.inWholeMilliseconds)
            println(7.microseconds.inWholeMicroseconds)
            println(7.nanoseconds.inWholeNanoseconds)
            println(3.minutes.inWholeMinutes)
            println(2.hours.inWholeHours)
            // 4 days expressed in hours: 4 * 24 = 96
            println(4.days.inWholeHours)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DurationStableUnitExtInt",
            expected:
                """
                1
                1500
                7
                7
                3
                2
                96
                """ + "\n"
        )
    }

    func testDurationStableUnitExtensionPropertiesLong() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.microseconds
        import kotlin.time.Duration.Companion.nanoseconds
        import kotlin.time.Duration.Companion.minutes
        import kotlin.time.Duration.Companion.hours
        import kotlin.time.Duration.Companion.days

        fun main() {
            println(5L.seconds.inWholeSeconds)
            println(2500L.milliseconds.inWholeMilliseconds)
            // 1_000_000 ns == 1 ms
            println(1_000_000L.nanoseconds.inWholeMilliseconds)
            println(5L.microseconds.inWholeMicroseconds)
            println(5L.minutes.inWholeSeconds)
            println(5L.hours.inWholeMinutes)
            println(5L.days.inWholeHours)
            println((-5L).hours.inWholeHours)
            println(0L.days.inWholeNanoseconds)

            println(9223372036854775807L.days.isInfinite())
            println(9223372036854775807L.hours.isInfinite())
            println(9223372036854775807L.minutes.isInfinite())
            println(9223372036854775807L.microseconds.isInfinite())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DurationStableUnitExtLong",
            expected:
                """
                5
                2500
                1
                5
                300
                300
                120
                -5
                0
                true
                true
                true
                true
                """ + "\n"
        )
    }

    func testDurationStableInWholeAccessors() throws {
        let source = """
        import kotlin.time.Duration.Companion.hours

        fun main() {
            val twoHours = 2.hours
            println(twoHours.inWholeHours)
            println(twoHours.inWholeMinutes)
            println(twoHours.inWholeSeconds)
            println(twoHours.inWholeMilliseconds)
            println(twoHours.inWholeMicroseconds)
            println(twoHours.inWholeNanoseconds)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DurationStableInWholeAccessors",
            expected:
                """
                2
                120
                7200
                7200000
                7200000000
                7200000000000
                """ + "\n"
        )
    }

    func testDurationStableNegativeLiteralDuration() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds
        import kotlin.time.Duration.Companion.milliseconds

        fun main() {
            val neg = (-5).seconds
            println(neg.inWholeSeconds)
            println(neg.isNegative())
            println(neg.isPositive())

            val neg2 = (-1500).milliseconds
            println(neg2.inWholeMilliseconds)
            println(neg2.isNegative())
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableNegativeLiteralDuration", expected: "-5\ntrue\nfalse\n-1500\ntrue\n")
    }

    func testDurationStableAbsoluteValue() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val neg = (-7).seconds
            val abs = neg.absoluteValue
            println(abs.inWholeSeconds)
            println(abs.isNegative())
            println(abs.isPositive())

            // absoluteValue of a positive duration is unchanged
            val pos = 3.seconds
            println(pos.absoluteValue.inWholeSeconds)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableAbsoluteValue", expected: "7\nfalse\ntrue\n3\n")
    }

    func testDurationStableIsFiniteIsInfinite() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val finite = 10.seconds
            println(finite.isFinite())
            println(finite.isInfinite())

            // Long.MAX_VALUE seconds overflows nanosecond Int64 -> saturation = Int64.max
            // which is the INFINITE sentinel in KSwiftK's Duration implementation.
            val huge = 9223372036854775807L.seconds
            println(huge.isInfinite())
            println(huge.isFinite())
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableIsFiniteInfinite", expected: "true\nfalse\ntrue\nfalse\n")
    }

    func testDurationStableCompanionConstants() throws {
        let source = """
        import kotlin.time.Duration

        fun main() {
            println(Duration.ZERO.inWholeSeconds)
            println(Duration.ZERO.isFinite())
            println(Duration.INFINITE.isInfinite())
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableCompanionConstants", expected: "0\ntrue\ntrue\n")
    }

    func testDurationStableIsoStringAndParse() throws {
        let source = """
        import kotlin.time.Duration
        import kotlin.time.Duration.Companion.nanoseconds

        fun main() {
            println(3.nanoseconds.toIsoString())
            println(Duration.parse("PT1H30M").toIsoString())
            println(Duration.parse("PT1H30M").inWholeMinutes)
            println(Duration.parse("1.5h").inWholeMinutes)
            println(Duration.parseOrNull("1 hour 30 minutes") == null)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DurationStableIsoStringAndParse",
            expected:
                """
                PT0.000000003S
                PT1H30M
                90
                90
                true
                """ + "\n"
        )
    }

    func testDurationStableParseIsoString() throws {
        let source = """
        import kotlin.time.Duration

        fun main() {
            println(Duration.parseIsoString("P1DT2H3M4.005S").inWholeSeconds)
            println(Duration.parseIsoStringOrNull("PT1H30M") == null)
            println(Duration.parseIsoStringOrNull("1h 30m") == null)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableParseIsoString", expected: "93784\nfalse\ntrue\n")
    }

    // KSP-471: Duration.Companion.parse/parseIsoString are Kotlin source (Duration.kt)
    // wrappers around the canThrow __kk_duration_parse/__kk_duration_parseIsoString
    // bridges. Verify the thrown exception actually propagates out of the Kotlin
    // source wrapper (not just the native bridge, which RuntimeDurationTests already
    // covers directly).
    func testDurationStableParseAndParseIsoStringThrowOnInvalidInput() throws {
        let source = """
        import kotlin.time.Duration

        fun main() {
            try {
                Duration.parse("not a duration")
            } catch (e: IllegalArgumentException) {
                println("iae-parse")
            }
            try {
                Duration.parseIsoString("not iso")
            } catch (e: IllegalArgumentException) {
                println("iae-parseIsoString")
            }
            println("done")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DurationStableParseThrows",
            expected: "iae-parse\niae-parseIsoString\ndone\n"
        )
    }

    func testDurationStableDoubleReceiverExtensionProperties() throws {
        let source = """
        import kotlin.time.Duration.Companion.days
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println(1.5.seconds.inWholeMilliseconds)
            println(1.25.days.inWholeHours)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableDoubleReceiverExtensions", expected: "1500\n30\n")
    }

    func testDurationStableNumericToDurationUnitOverloads() throws {
        let source = """
        import kotlin.time.DurationUnit
        import kotlin.time.toDuration

        fun main() {
            val seconds = 2.toDuration(DurationUnit.SECONDS)
            val milliseconds = 1500L.toDuration(DurationUnit.MILLISECONDS)
            val minutes = 1.5.toDuration(DurationUnit.MINUTES)

            println(seconds.inWholeSeconds)
            println(milliseconds.inWholeMilliseconds)
            println(minutes.inWholeSeconds)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableToDurationUnit", expected: "2\n1500\n90\n")
    }

    func testDurationStableDurationDivisionReturnsDouble() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println(3.seconds / 2.seconds)
            println(1.seconds / 4.seconds)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableDivisionReturnsDouble", expected: "1.5\n0.25\n")
    }

    func testDurationStableInWholeDays() throws {
        let source = """
        import kotlin.time.Duration.Companion.days
        import kotlin.time.Duration.Companion.hours

        fun main() {
            println(2.days.inWholeDays)
            println(36.hours.inWholeDays)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableInWholeDays", expected: "2\n1\n")
    }

    func testDurationStableToComponentsOverloads() throws {
        let source = """
        import kotlin.time.Duration.Companion.days
        import kotlin.time.Duration.Companion.hours
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.minutes
        import kotlin.time.Duration.Companion.nanoseconds
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val composite = 1.days + 2.hours + 3.minutes + 4.seconds + 5.nanoseconds
            composite.toComponents { days, hours, minutes, seconds, nanoseconds ->
                println(days)
                println(hours)
                println(minutes)
                println(seconds)
                println(nanoseconds)
            }
            composite.toComponents { hours, minutes, seconds, nanoseconds ->
                println(hours)
                println(minutes)
                println(seconds)
                println(nanoseconds)
            }
            composite.toComponents { minutes, seconds, nanoseconds ->
                println(minutes)
                println(seconds)
                println(nanoseconds)
            }
            (-1500).milliseconds.toComponents { seconds, nanoseconds ->
                println(seconds)
                println(nanoseconds)
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableToComponents", expected: "1\n2\n3\n4\n5\n26\n3\n4\n5\n1563\n4\n5\n-1\n-500000000\n")
    }

    func testDurationStableArithmeticAddSubtract() throws {
        let source = """
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println((2.seconds + 500.milliseconds).inWholeMilliseconds)
            println((2.seconds - 500.milliseconds).inWholeMilliseconds)
            println((500.milliseconds - 2.seconds).isNegative())
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableAddSubtract", expected: "2500\n1500\ntrue\n")
    }

    func testDurationStableArithmeticTimesDiv() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println((10.seconds * 2).inWholeSeconds)
            println((10.seconds / 2).inWholeSeconds)
            println((10.seconds * 0).inWholeSeconds)
            println((10.seconds * 0).isPositive())
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableTimesDiv", expected: "20\n5\n0\nfalse\n")
    }

    func testDurationStableUnaryMinus() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val neg = -(5.seconds)
            println(neg.inWholeSeconds)
            println(neg.isNegative())
            println((-neg).inWholeSeconds)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableUnaryMinus", expected: "-5\ntrue\n5\n")
    }

    func testDurationStableComparisonOperators() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val shorter = 1.seconds
            val longer = 2.seconds
            println(shorter < longer)
            println(longer > shorter)
            println(shorter <= shorter)
            println(shorter >= longer)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableComparisonOperators", expected: "true\ntrue\ntrue\nfalse\n")
    }

    func testDurationStableInfiniteAddSaturation() throws {
        let source = """
        import kotlin.time.Duration
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val inf = Duration.INFINITE
            println(inf.isInfinite())
            println((inf + 1.seconds).isInfinite())
            val diff = inf - inf
            println(diff.isInfinite())
            println(diff.isPositive())
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableInfiniteAddSaturation", expected: "true\ntrue\nfalse\nfalse\n")
    }

    func testDurationStableDivByZeroSaturatesToInfinite() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            println((5.seconds / 0).isInfinite())
            println(((-5).seconds / 0).isInfinite())
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableDivByZero", expected: "true\ntrue\n")
    }

    func testDurationStableNegativeZeroEqualsPositiveZero() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val zero = 0.seconds
            val negZero = -zero
            println(zero.inWholeSeconds)
            println(negZero.inWholeSeconds)
            println(zero.isNegative())
            println(negZero.isNegative())
            println(zero == negZero)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableNegativeZeroEqualsPositiveZero", expected: "0\n0\nfalse\nfalse\ntrue\n")
    }

    func testDurationStableZeroDurationPredicates() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val zero = 0.seconds
            println(zero.inWholeSeconds)
            println(zero.isPositive())
            println(zero.isNegative())
            println(zero.isFinite())
            println(zero.isInfinite())
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableZeroPredicates", expected: "0\nfalse\nfalse\ntrue\nfalse\n")
    }

    func testDurationStableInWholeNanoseconds() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            // 10 seconds = 10_000_000_000 nanoseconds — fits in Long
            val d = 10.seconds
            println(d.inWholeNanoseconds)

            // Negative durations yield negative nanosecond count
            val neg = (-3).seconds
            println(neg.inWholeNanoseconds)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableInWholeNs", expected: "10000000000\n-3000000000\n")
    }

    func testDurationStableCrossUnitConsistency() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds
        import kotlin.time.Duration.Companion.milliseconds
        import kotlin.time.Duration.Companion.microseconds
        import kotlin.time.Duration.Companion.nanoseconds
        import kotlin.time.Duration.Companion.minutes
        import kotlin.time.Duration.Companion.hours
        import kotlin.time.Duration.Companion.days

        fun main() {
            // Different units representing the same span should have identical inWhole* values
            println(60.seconds.inWholeMinutes)   // == 1
            println(1.minutes.inWholeSeconds)     // == 60

            println(60.minutes.inWholeHours)      // == 1
            println(1.hours.inWholeMinutes)        // == 60

            println(24.hours.inWholeHours)         // == 24
            println(1.days.inWholeHours)           // == 24

            // Nanosecond granularity
            println(1.milliseconds.inWholeNanoseconds)    // 1_000_000
            println(1000.microseconds.inWholeNanoseconds) // 1_000_000
            println(1_000_000.nanoseconds.inWholeNanoseconds) // 1_000_000
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "DurationStableCrossUnit",
            expected:
                """
                1
                60
                1
                60
                24
                24
                1000000
                1000000
                1000000
                """ + "\n"
        )
    }

    func testDurationStableBoundaryPredicatesRequireNoOptIn() throws {
        let source = """
        import kotlin.time.Duration.Companion.seconds

        fun main() {
            val d = 3.seconds
            println(d.isPositive())
            println(d.isNegative())
            println(d.isFinite())
            println(d.isInfinite())
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationStableBoundaryPredicates", expected: "true\nfalse\ntrue\nfalse\n")
    }

    func testDurationUnitToTimeUnitConversion() throws {
        let source = """
        import java.util.concurrent.TimeUnit
        import kotlin.time.DurationUnit
        import kotlin.time.toTimeUnit

        fun label(unit: DurationUnit): String = when (unit.toTimeUnit()) {
            TimeUnit.NANOSECONDS -> "ns"
            TimeUnit.MICROSECONDS -> "us"
            TimeUnit.MILLISECONDS -> "ms"
            TimeUnit.SECONDS -> "s"
            TimeUnit.MINUTES -> "min"
            TimeUnit.HOURS -> "h"
            TimeUnit.DAYS -> "d"
        }

        fun main() {
            println(label(DurationUnit.NANOSECONDS))
            println(label(DurationUnit.SECONDS))
            println(label(DurationUnit.DAYS))
            println(DurationUnit.MINUTES.toTimeUnit() == TimeUnit.MINUTES)
            println(DurationUnit.HOURS.toTimeUnit() == TimeUnit.SECONDS)
        }
        """

        try assertKotlinOutput(source, moduleName: "DurationUnitToTimeUnit", expected: "ns\ns\nd\ntrue\nfalse\n")
    }
}

