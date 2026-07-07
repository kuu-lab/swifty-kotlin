package kotlin.time

// KSP-472
// Instant member accessors, arithmetic, comparison, and until()/elapsed().
// Migration source: Sources/Runtime/RuntimeInstant.swift
//   kk_instant_epoch_seconds, kk_instant_nano_of_second,
//   kk_instant_is_distant_past, kk_instant_is_distant_future,
//   kk_instant_plus_duration, kk_instant_minus_duration, kk_instant_compare,
//   kk_instant_until
//
// All operations delegate to __kk_instant_* bridges backed by kk_* ABI
// functions. Bridge stubs are registered in
// HeaderHelpers+SyntheticInstantStubs.swift.
//
// Instant.now() / Instant.fromEpochMilliseconds() stay as direct native
// bridges (kk_instant_now / kk_instant_from_epoch_millis): they are
// companion factory methods, and Kotlin source cannot declare an extension
// whose receiver is Instant.Companion.

public val Instant.epochSeconds: Long
    get() = this.__kk_instant_epoch_seconds()

public val Instant.nanoOfSecond: Int
    get() = this.__kk_instant_nano_of_second()

public val Instant.isDistantPast: Boolean
    get() = this.__kk_instant_is_distant_past()

public val Instant.isDistantFuture: Boolean
    get() = this.__kk_instant_is_distant_future()

public operator fun Instant.plus(duration: Duration): Instant =
    this.__kk_instant_plus_duration(duration)

public operator fun Instant.minus(duration: Duration): Instant =
    this.__kk_instant_minus_duration(duration)

public operator fun Instant.compareTo(other: Instant): Int =
    this.__kk_instant_compare(other)

public fun Instant.until(other: Instant): Duration =
    this.__kk_instant_until(other)

public fun Instant.elapsed(): Duration =
    this.__kk_instant_until(Instant.now())
