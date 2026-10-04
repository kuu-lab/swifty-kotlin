import kotlin.time.Clock
import kotlin.time.Instant

class FixedClock : Clock {
    override fun now(): Instant = Instant.fromEpochMilliseconds(1234L)
}

fun main() {
    val clock: Clock? = FixedClock()
    val nilClock: Clock? = null
    println(clock?.now()?.epochSeconds)
    println(nilClock?.now()?.epochSeconds)

    val nonNullClock: Clock = FixedClock()
    println(nonNullClock.now().epochSeconds)
}
