import kotlin.time.Instant
import kotlin.time.isDistantFuture
import kotlin.time.isDistantPast

// KUU-1597 Sema owner: pin Instant factory/parser and boundary-property resolution; runtime outcomes stay in Scripts/diff_cases/stdlib_kotlin_time_Instant_Companion_Companion_n.kt.
fun main() {
    val fromLong: Instant = Instant.fromEpochSeconds(0L, 123_456_789L)
    val fromInt: Instant = Instant.fromEpochSeconds(0L, 123_456_789)
    val parsed: Instant = Instant.parse("1970-01-01T00:00:00.123456789Z")
    val parsedOrNull: Instant? = Instant.parseOrNull("1970-01-01T00:00:00Z")
    val distantPast: Boolean = Instant.DISTANT_PAST.isDistantPast
    val distantFuture: Boolean = Instant.DISTANT_FUTURE.isDistantFuture
}
