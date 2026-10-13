import kotlin.time.Clock
import kotlin.time.Instant

// KUU-1597 Sema owner: pin Clock.Companion/System singleton types and custom Clock.now; identity/current-time values stay in Scripts/diff_cases/stdlib_kotlin_time_Clock_n_n.kt.
class FixedClock : Clock {
    override fun now(): Instant = Instant.fromEpochMilliseconds(1234L)
}

fun main() {
    val companion: Clock.Companion = Clock.Companion
    val system: Clock.System = Clock.System
    val asClock: Clock = Clock.System
    val custom: Clock = FixedClock()
    val now: Instant = custom.now()
}
