package kotlin.ranges

external fun Byte.coerceAtLeast(minimumValue: Byte): Byte
external fun Byte.coerceAtMost(maximumValue: Byte): Byte
external fun Short.coerceAtLeast(minimumValue: Short): Short
external fun Short.coerceAtMost(maximumValue: Short): Short
external fun Int.coerceAtLeast(minimumValue: Int): Int
external fun Int.coerceAtMost(maximumValue: Int): Int
external fun Long.coerceAtLeast(minimumValue: Long): Long
external fun Long.coerceAtMost(maximumValue: Long): Long
external fun Float.coerceAtLeast(minimumValue: Float): Float
external fun Float.coerceAtMost(maximumValue: Float): Float
external fun Double.coerceAtLeast(minimumValue: Double): Double
external fun Double.coerceAtMost(maximumValue: Double): Double

external fun Long.coerceIn(minimumValue: Long, maximumValue: Long): Long
external fun Double.coerceIn(minimumValue: Double, maximumValue: Double): Double
external fun <T : Comparable<T>> T.coerceIn(minimumValue: T?, maximumValue: T?): T

public infix fun Int.until(to: Int): IntRange =
    if (to == Int.MIN_VALUE) IntRange(1, 0) else IntRange(this, to - 1)

// `x in progression` resolves through the kotlin.ranges package extension
// rather than an IntProgression member, matching upstream Iterable.contains.
public operator fun IntProgression.contains(value: Int): Boolean = null!!

// `step` is an operator candidate only with the operator flag; bundled
// declarations are exempt from the legal-operator-name check the same way
// the common ProgressionConstructors.kt declaration is.
public operator infix fun IntProgression.step(step: Int): IntProgression = null!!

// Reversing swaps the endpoints and negates the step; the specialized
// progression overload keeps the IntProgression return type.
public fun IntProgression.reversed(): IntProgression = null!!

public inline fun IntRange.all(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}
