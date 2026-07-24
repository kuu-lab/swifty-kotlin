package kotlin.time

// KSP-472
// Instant member accessors, arithmetic, comparison, and elapsed().
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
// Instant.now() / Instant.fromEpochMilliseconds() are now Kotlin-source
// companion-object extensions that delegate to __kk_instant_* bridges.

public val Instant.epochSeconds: Long
    get() = this.__kk_instant_epoch_seconds()

public val Instant.nanosecondsOfSecond: Int
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

// Real kotlin.time.Instant has no until(); the duration between two instants
// is obtained via this minus operator overload (t2 - t1), matching the real
// stdlib's `operator fun minus(other: Instant): Duration`.
public operator fun Instant.minus(other: Instant): Duration =
    other.__kk_instant_until(this)

public fun Instant.elapsed(): Duration =
    this.__kk_instant_until(Instant.now())

// KSP-472: companion factories

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_instant_now")
private external fun __kk_instant_now(): Instant

@KsSymbolName("kk_instant_from_epoch_millis")
private external fun __kk_instant_from_epoch_millis(epochMilliseconds: Long): Instant

public fun Instant.Companion.now(): Instant = __kk_instant_now()

public fun Instant.Companion.fromEpochMilliseconds(epochMilliseconds: Long): Instant =
    __kk_instant_from_epoch_millis(epochMilliseconds)
