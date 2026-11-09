package java.time

/** A clock providing access to the current instant and time-zone. */
public class Clock private constructor(
    public val zone: ZoneId,
) {
    public fun getZone(): ZoneId = zone

    public fun instant(): Instant = Instant.now()

    public fun millis(): Long = instant().toEpochMilli()

    public fun withZone(zone: ZoneId): Clock = Clock(zone)

    override fun toString(): String = "SystemClock[" + zone.id + "]"

    public companion object {
        public fun systemUTC(): Clock = Clock(ZoneOffset.UTC)

        public fun systemDefaultZone(): Clock = Clock(ZoneId.systemDefault())

        public fun system(zone: ZoneId): Clock = Clock(zone)
    }
}
