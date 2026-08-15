package kotlin.time

// KSP-683: DurationUnit is a real bundled enum. Java TimeUnit conversion keeps
// its native interop registration because the Java enum is a compiler-provided
// platform type rather than a bundled Kotlin declaration.
public enum class DurationUnit {
    NANOSECONDS,
    MICROSECONDS,
    MILLISECONDS,
    SECONDS,
    MINUTES,
    HOURS,
    DAYS
}
