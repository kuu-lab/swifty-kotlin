import kotlin.time.Clock
import kotlin.time.Instant

class FixedClock : Clock {
    override fun now(): Instant = Instant.fromEpochMilliseconds(1234L)
}

fun main() {
    val companion: Clock.Companion = Clock.Companion
    val system: Clock.System = Clock.System
    val asClock: Clock = Clock.System
    val custom: Clock = FixedClock()
    println(companion === Clock.Companion)
    println(system === Clock.System)
    println(asClock === Clock.System)
    println(custom.now().epochSeconds)
}
