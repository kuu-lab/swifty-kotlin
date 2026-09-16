import kotlin.time.Instant
import kotlin.time.isDistantFuture
import kotlin.time.isDistantPast

fun main() {
    val fromLong = Instant.fromEpochSeconds(0L, 123_456_789L)
    val fromInt = Instant.fromEpochSeconds(0L, 123_456_789)
    val parsed = Instant.parse("1970-01-01T00:00:00.123456789Z")
    val parsedOrNull = Instant.parseOrNull("1970-01-01T00:00:00Z")

    println(fromLong.nanosecondsOfSecond == fromInt.nanosecondsOfSecond)
    println(fromLong.nanosecondsOfSecond == parsed.nanosecondsOfSecond)
    println(parsedOrNull !== null)
    println(Instant.DISTANT_PAST.isDistantPast)
    println(Instant.DISTANT_FUTURE.isDistantFuture)
}
