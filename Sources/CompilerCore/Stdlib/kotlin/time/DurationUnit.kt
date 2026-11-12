package kotlin.time

// JVM TimeUnit interop is target-out for KSwiftK and is not part of this
// common Kotlin surface.
public enum class DurationUnit {
    NANOSECONDS,
    MICROSECONDS,
    MILLISECONDS,
    SECONDS,
    MINUTES,
    HOURS,
    DAYS
}
