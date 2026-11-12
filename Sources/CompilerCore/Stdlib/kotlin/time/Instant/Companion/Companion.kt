package kotlin.time

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_instant_from_epoch_seconds")
private external fun __kk_instant_from_epoch_seconds(
    epochSeconds: Long,
    nanosecondAdjustment: Long
): Instant

private const val INSTANT_NANOS_PER_SECOND: Long = 1_000_000_000L

public val Instant.Companion.DISTANT_PAST: Instant
    get() = instantFromEpochSeconds(INSTANT_DISTANT_PAST_SECONDS, 999_999_999L)

public val Instant.Companion.DISTANT_FUTURE: Instant
    get() = instantFromEpochSeconds(INSTANT_DISTANT_FUTURE_SECONDS, 0L)

public fun Instant.Companion.fromEpochSeconds(
    epochSeconds: Long,
    nanosecondAdjustment: Long = 0L
): Instant = instantFromEpochSeconds(epochSeconds, nanosecondAdjustment)

private fun instantFromEpochSeconds(epochSeconds: Long, nanosecondAdjustment: Long): Instant {
    val secondsAdjustment = instantFloorDiv(nanosecondAdjustment, INSTANT_NANOS_PER_SECOND)
    val normalizedSeconds = instantSaturatingAdd(epochSeconds, secondsAdjustment)
    if (normalizedSeconds < INSTANT_MIN_SECOND) {
        return __kk_instant_from_epoch_seconds(INSTANT_MIN_SECOND, 0L)
    }
    if (normalizedSeconds > INSTANT_MAX_SECOND) {
        return __kk_instant_from_epoch_seconds(INSTANT_MAX_SECOND, 999_999_999L)
    }
    val normalizedNanos = nanosecondAdjustment - secondsAdjustment * INSTANT_NANOS_PER_SECOND
    return __kk_instant_from_epoch_seconds(normalizedSeconds, normalizedNanos)
}

public fun Instant.Companion.fromEpochSeconds(
    epochSeconds: Long,
    nanosecondAdjustment: Int
): Instant = instantFromEpochSeconds(epochSeconds, nanosecondAdjustment.toLong())

public fun Instant.Companion.parse(input: CharSequence): Instant {
    return instantParseOrNull(input.toString())
        ?: throw IllegalArgumentException("Invalid instant string: $input")
}

public fun Instant.Companion.parseOrNull(input: CharSequence): Instant? =
    instantParseOrNull(input.toString())

private fun instantFloorDiv(value: Long, divisor: Long): Long {
    val quotient = value / divisor
    val remainder = value % divisor
    return if (remainder < 0L) quotient - 1L else quotient
}

private fun instantSaturatingAdd(lhs: Long, rhs: Long): Long {
    if (rhs > 0L && lhs > Long.MAX_VALUE - rhs) return Long.MAX_VALUE
    if (rhs < 0L && lhs < Long.MIN_VALUE - rhs) return Long.MIN_VALUE
    return lhs + rhs
}
