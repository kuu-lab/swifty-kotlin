// KUU-1067: large ns values switch to finite ms storage, not infinity.
import kotlin.time.*
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Duration.Companion.microseconds
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Duration.Companion.days

fun describeDuration(d: Duration) {
    println(d)
    println(d.isFinite())
    println(d.inWholeNanoseconds)
    println(d.inWholeMicroseconds)
    println(d.inWholeMilliseconds)
    println(d.inWholeSeconds)
    println(d.inWholeDays)
    println(d.toIsoString())
    println(d.toComponents { days, hours, minutes, seconds, nanos -> "$days/$hours/$minutes/$seconds/$nanos" })
    println(d.hashCode() == (d as Any).hashCode())
}

fun main() {
    println(Long.MAX_VALUE.nanoseconds)
    println(Long.MIN_VALUE.nanoseconds)
    println(Long.MAX_VALUE.milliseconds)
    val values = listOf(0L, 1L, -1L, 4_611_686_018_426_999_999L,
        4_611_686_018_427_000_000L, 4_611_686_018_427_000_001L,
        -4_611_686_018_426_999_999L, -4_611_686_018_427_000_000L,
        -4_611_686_018_427_000_001L, Long.MAX_VALUE - 1L, Long.MAX_VALUE, Long.MIN_VALUE)
    for (value in values) describeDuration(value.nanoseconds)
    describeDuration(Long.MAX_VALUE.microseconds)
    describeDuration(Long.MIN_VALUE.microseconds)
    describeDuration(4_611_686_018_427_387_902L.milliseconds)
    describeDuration((-4_611_686_018_427_387_902L).milliseconds)
    describeDuration(4_611_686_018_427_387_903L.milliseconds)
    describeDuration(Long.MIN_VALUE.milliseconds)
    println(Long.MAX_VALUE.seconds.isInfinite())
    println(Long.MAX_VALUE.days.isInfinite())
    println(Long.MAX_VALUE.toDouble().nanoseconds)
    println(Long.MIN_VALUE.toDouble().nanoseconds)
    println(Long.MAX_VALUE.toDouble().microseconds.isFinite())
    println(Long.MAX_VALUE.toDouble().milliseconds.isInfinite())

    val edge = 4_611_686_018_426_999_999L.nanoseconds
    val next = 4_611_686_018_427_000_000L.nanoseconds
    println(edge + 1.nanoseconds == next)
    println(next - 1.nanoseconds == next)
    println(next - 1.milliseconds == 4_611_686_018_426_000_000L.nanoseconds)
    println(edge < next)
    println(-edge > -next)
    val maximum = Long.MAX_VALUE.nanoseconds
    val minimum = Long.MIN_VALUE.nanoseconds
    println(-minimum == maximum)
    println(minimum.absoluteValue == maximum)
    println(maximum + minimum)
    println(maximum * 2)
    println((maximum * 2) / 2 == maximum)
    println(maximum / 3)
    println(maximum * Int.MAX_VALUE)
    println(edge * Int.MAX_VALUE)
    println(next / Int.MAX_VALUE)
    println(maximum * 0.5)
    println(maximum / 2.5)
    println(maximum / minimum)
    println(maximum.toLong(DurationUnit.MILLISECONDS))
    println(maximum.toInt(DurationUnit.DAYS))
    println(maximum.toDouble(DurationUnit.MILLISECONDS))
    println(maximum < Duration.INFINITE)
    println(minimum > -Duration.INFINITE)
    println((Duration.INFINITE / 2).isInfinite())
    println((-Duration.INFINITE).absoluteValue == Duration.INFINITE)
    println(Duration.INFINITE.isPositive())
    println((-Duration.INFINITE).isNegative())
}
