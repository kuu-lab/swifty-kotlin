package kotlin.time

// KSP-683: DurationUnit is a real bundled enum. JVM TimeUnit interop is
// target-out for KSwiftK and is not part of this common Kotlin surface.
public enum class DurationUnit {
    NANOSECONDS,
    MICROSECONDS,
    MILLISECONDS,
    SECONDS,
    MINUTES,
    HOURS,
    DAYS
}
