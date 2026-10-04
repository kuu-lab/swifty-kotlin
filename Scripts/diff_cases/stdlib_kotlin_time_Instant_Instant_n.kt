// JAVA_FLAGS: -ea
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Instant

fun main() {
    val instant = Instant.fromEpochMilliseconds(1_000L) + 500.milliseconds
    val same = Instant.fromEpochMilliseconds(1_500L)
    val different: Any = "not-an-instant"
    val asAny: Any = instant
    val sameAsAny: Any = same
    val negative = Instant.fromEpochMilliseconds(-500L)

    println(instant.equals(null))
    println(instant.equals(same))
    println(instant.equals(different))
    println(instant == same)
    println(asAny.equals(sameAsAny))
    println(instant.hashCode())
    println(asAny.hashCode())
    println(instant.toEpochMilliseconds())
    println(negative.toEpochMilliseconds())
    println(Instant.fromEpochMilliseconds(-9223372036854775807L - 1L).toEpochMilliseconds())
    println(Instant.fromEpochMilliseconds(9223372036854775807L).toEpochMilliseconds())
    println(instant.toString())
    println(asAny.toString())
    println(negative.toString())
    println((negative as Any).toString())

    try {
        assert(false) { instant }
    } catch (error: AssertionError) {
        println(error.message)
    }
}
