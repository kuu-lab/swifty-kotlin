package kotlin.ranges
fun Byte.coerceAtLeast(minimumValue: Byte): Byte = if (this < minimumValue) minimumValue else this
fun Byte.coerceAtMost(maximumValue: Byte): Byte = if (this > maximumValue) maximumValue else this
fun Short.coerceAtLeast(minimumValue: Short): Short = if (this < minimumValue) minimumValue else this
fun Short.coerceAtMost(maximumValue: Short): Short = if (this > maximumValue) maximumValue else this
fun Int.coerceAtLeast(minimumValue: Int): Int = if (this < minimumValue) minimumValue else this
fun Int.coerceAtMost(maximumValue: Int): Int = if (this > maximumValue) maximumValue else this
fun Long.coerceAtLeast(minimumValue: Long): Long = if (this < minimumValue) minimumValue else this
fun Long.coerceAtMost(maximumValue: Long): Long = if (this > maximumValue) maximumValue else this
fun Float.coerceAtLeast(minimumValue: Float): Float = if (this < minimumValue) minimumValue else this
fun Float.coerceAtMost(maximumValue: Float): Float = if (this > maximumValue) maximumValue else this
fun Double.coerceAtLeast(minimumValue: Double): Double = if (this < minimumValue) minimumValue else this
fun Double.coerceAtMost(maximumValue: Double): Double = if (this > maximumValue) maximumValue else this

public infix fun Int.until(to: Int): IntRange =
    if (to == Int.MIN_VALUE) IntRange(1, 0) else IntRange(this, to - 1)

public inline fun IntRange.all(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}
