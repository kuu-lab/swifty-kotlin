@file:OptIn(kotlinx.atomicfu.locks.ExperimentalThreadBlockingApi::class)

package java.util.concurrent

import kotlinx.atomicfu.locks.ParkingSupport
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.DurationUnit
import kotlin.time.toDuration

// KUU-3059: java.util.concurrent.TimeUnit. Conversions follow the JVM
// multiply/divide semantics with saturating multiplication; `sleep` parks the
// calling thread on the atomicfu parker (no timer thread needed).

public enum class TimeUnit {
    NANOSECONDS,
    MICROSECONDS,
    MILLISECONDS,
    SECONDS,
    MINUTES,
    HOURS,
    DAYS;

    private val nanosScale: Long
        get() = when (this) {
            NANOSECONDS -> 1L
            MICROSECONDS -> 1_000L
            MILLISECONDS -> 1_000_000L
            SECONDS -> 1_000_000_000L
            MINUTES -> 60_000_000_000L
            HOURS -> 3_600_000_000_000L
            DAYS -> 86_400_000_000_000L
        }

    public fun convert(sourceDuration: Long, sourceUnit: TimeUnit): Long {
        val up = sourceUnit.nanosScale / nanosScale
        if (up >= 1L) return saturatingMul(sourceDuration, up)
        val down = nanosScale / sourceUnit.nanosScale
        return sourceDuration / down
    }

    public fun toNanos(duration: Long): Long = NANOSECONDS.convert(duration, this)

    public fun toMicros(duration: Long): Long = MICROSECONDS.convert(duration, this)

    public fun toMillis(duration: Long): Long = MILLISECONDS.convert(duration, this)

    public fun toSeconds(duration: Long): Long = SECONDS.convert(duration, this)

    public fun toMinutes(duration: Long): Long = MINUTES.convert(duration, this)

    public fun toHours(duration: Long): Long = HOURS.convert(duration, this)

    public fun toDays(duration: Long): Long = DAYS.convert(duration, this)

    public fun sleep(timeout: Long) {
        if (timeout > 0L) {
            ParkingSupport.park(toNanos(timeout).nanoseconds)
        }
    }

    public fun toDurationUnit(): DurationUnit = when (this) {
        NANOSECONDS -> DurationUnit.NANOSECONDS
        MICROSECONDS -> DurationUnit.MICROSECONDS
        MILLISECONDS -> DurationUnit.MILLISECONDS
        SECONDS -> DurationUnit.SECONDS
        MINUTES -> DurationUnit.MINUTES
        HOURS -> DurationUnit.HOURS
        DAYS -> DurationUnit.DAYS
    }

    public companion object {
        public fun of(unit: DurationUnit): TimeUnit = when (unit) {
            DurationUnit.NANOSECONDS -> NANOSECONDS
            DurationUnit.MICROSECONDS -> MICROSECONDS
            DurationUnit.MILLISECONDS -> MILLISECONDS
            DurationUnit.SECONDS -> SECONDS
            DurationUnit.MINUTES -> MINUTES
            DurationUnit.HOURS -> HOURS
            DurationUnit.DAYS -> DAYS
        }
    }
}

internal fun saturatingMul(value: Long, scale: Long): Long = when {
    value > Long.MAX_VALUE / scale -> Long.MAX_VALUE
    value < Long.MIN_VALUE / scale -> Long.MIN_VALUE
    else -> value * scale
}

internal fun TimeUnit.toDurationOf(timeout: Long): Duration = timeout.toDuration(toDurationUnit())
