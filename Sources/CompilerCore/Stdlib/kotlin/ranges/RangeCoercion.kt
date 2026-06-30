package kotlin.ranges

// MIGRATION-RANGE-003
// coerceIn / coerceAtLeast / coerceAtMost migrated to Kotlin source for
// Int, Long, Double, Float.
//
// NOTE: CallLowerer dispatch (kk_int_coerceIn etc.) is intentionally kept as
// bridge compatibility helpers while stdlib-source dispatch is rolled out
// incrementally. These bodies provide canonical type definitions for Sema.

public fun Int.coerceIn(minimumValue: Int, maximumValue: Int): Int {
    if (minimumValue > maximumValue) throw IllegalArgumentException(
        "Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue."
    )
    if (this < minimumValue) return minimumValue
    if (this > maximumValue) return maximumValue
    return this
}

public fun Int.coerceAtLeast(minimumValue: Int): Int = if (this < minimumValue) minimumValue else this

public fun Int.coerceAtMost(maximumValue: Int): Int = if (this > maximumValue) maximumValue else this

public fun Long.coerceIn(minimumValue: Long, maximumValue: Long): Long {
    if (minimumValue > maximumValue) throw IllegalArgumentException(
        "Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue."
    )
    if (this < minimumValue) return minimumValue
    if (this > maximumValue) return maximumValue
    return this
}

public fun Long.coerceAtLeast(minimumValue: Long): Long = if (this < minimumValue) minimumValue else this

public fun Long.coerceAtMost(maximumValue: Long): Long = if (this > maximumValue) maximumValue else this

public fun Double.coerceIn(minimumValue: Double, maximumValue: Double): Double {
    if (minimumValue > maximumValue) throw IllegalArgumentException(
        "Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue."
    )
    if (this < minimumValue) return minimumValue
    if (this > maximumValue) return maximumValue
    return this
}

public fun Double.coerceAtLeast(minimumValue: Double): Double = if (this < minimumValue) minimumValue else this

public fun Double.coerceAtMost(maximumValue: Double): Double = if (this > maximumValue) maximumValue else this

public fun Float.coerceIn(minimumValue: Float, maximumValue: Float): Float {
    if (minimumValue > maximumValue) throw IllegalArgumentException(
        "Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue."
    )
    if (this < minimumValue) return minimumValue
    if (this > maximumValue) return maximumValue
    return this
}

public fun Float.coerceAtLeast(minimumValue: Float): Float = if (this < minimumValue) minimumValue else this

public fun Float.coerceAtMost(maximumValue: Float): Float = if (this > maximumValue) maximumValue else this
