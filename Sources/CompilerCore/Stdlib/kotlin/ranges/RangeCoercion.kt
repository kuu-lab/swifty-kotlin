package kotlin.ranges

// MIGRATION-RANGE-003
// coerceIn / coerceAtLeast / coerceAtMost migrated to Kotlin source for
// Int, Long, Double, Float, Byte, Short.

public fun Int.coerceIn(minimumValue: Int, maximumValue: Int): Int {
    if (minimumValue > maximumValue) {
        throw IllegalArgumentException("Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue.")
    }
    return if (this < minimumValue) minimumValue else if (this > maximumValue) maximumValue else this
}

public fun Int.coerceAtLeast(minimumValue: Int): Int = if (this < minimumValue) minimumValue else this

public fun Int.coerceAtMost(maximumValue: Int): Int = if (this > maximumValue) maximumValue else this

public fun Int.coerceIn(range: IntRange): Int {
    if (range.isEmpty()) {
        throw IllegalArgumentException("Cannot coerce value to an empty range: maximum ${range.last} is less than minimum ${range.first}.")
    }
    return if (this < range.first) range.first else if (this > range.last) range.last else this
}

public fun Long.coerceIn(minimumValue: Long, maximumValue: Long): Long {
    if (minimumValue > maximumValue) {
        throw IllegalArgumentException("Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue.")
    }
    return if (this < minimumValue) minimumValue else if (this > maximumValue) maximumValue else this
}

public fun Long.coerceAtLeast(minimumValue: Long): Long = if (this < minimumValue) minimumValue else this

public fun Long.coerceAtMost(maximumValue: Long): Long = if (this > maximumValue) maximumValue else this

public fun Long.coerceIn(range: LongRange): Long {
    if (range.isEmpty()) {
        throw IllegalArgumentException("Cannot coerce value to an empty range: maximum ${range.last} is less than minimum ${range.first}.")
    }
    return if (this < range.first) range.first else if (this > range.last) range.last else this
}

public fun Double.coerceIn(minimumValue: Double, maximumValue: Double): Double {
    if (minimumValue > maximumValue) {
        throw IllegalArgumentException("Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue.")
    }
    return if (this < minimumValue) minimumValue else if (this > maximumValue) maximumValue else this
}

public fun Double.coerceAtLeast(minimumValue: Double): Double = if (this < minimumValue) minimumValue else this

public fun Double.coerceAtMost(maximumValue: Double): Double = if (this > maximumValue) maximumValue else this

public fun Float.coerceIn(minimumValue: Float, maximumValue: Float): Float {
    if (minimumValue > maximumValue) {
        throw IllegalArgumentException("Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue.")
    }
    return if (this < minimumValue) minimumValue else if (this > maximumValue) maximumValue else this
}

public fun Float.coerceAtLeast(minimumValue: Float): Float = if (this < minimumValue) minimumValue else this

public fun Float.coerceAtMost(maximumValue: Float): Float = if (this > maximumValue) maximumValue else this

public fun Byte.coerceIn(minimumValue: Byte, maximumValue: Byte): Byte {
    if (minimumValue > maximumValue) {
        throw IllegalArgumentException("Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue.")
    }
    return if (this < minimumValue) minimumValue else if (this > maximumValue) maximumValue else this
}

public fun Byte.coerceAtLeast(minimumValue: Byte): Byte = if (this < minimumValue) minimumValue else this

public fun Byte.coerceAtMost(maximumValue: Byte): Byte = if (this > maximumValue) maximumValue else this

public fun Short.coerceIn(minimumValue: Short, maximumValue: Short): Short {
    if (minimumValue > maximumValue) {
        throw IllegalArgumentException("Cannot coerce value to an empty range: maximum $maximumValue is less than minimum $minimumValue.")
    }
    return if (this < minimumValue) minimumValue else if (this > maximumValue) maximumValue else this
}

public fun Short.coerceAtLeast(minimumValue: Short): Short = if (this < minimumValue) minimumValue else this

public fun Short.coerceAtMost(maximumValue: Short): Short = if (this > maximumValue) maximumValue else this
