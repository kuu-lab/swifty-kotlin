// KSP-641: generic Comparable and ClosedFloatingPointRange coercion.

class Score(val value: Int) : Comparable<Score> {
    override fun compareTo(other: Score): Int = value.compareTo(other.value)
}

fun catchesIllegalArgument(action: () -> Unit): Boolean {
    return try {
        action()
        false
    } catch (e: IllegalArgumentException) {
        true
    }
}

fun main() {
    // Nullable bounds are unbounded on the missing side.
    println(Score(5).coerceIn(null, Score(3)).value)
    println(Score(5).coerceIn(Score(7), null).value)
    println(Score(5).coerceIn(null, null).value)

    // Custom Comparable values use compareTo and reject reversed bounds.
    println(Score(5).coerceIn(Score(1), Score(10)).value)
    println(catchesIllegalArgument { Score(5).coerceIn(Score(10), Score(1)) })

    // ClosedFloatingPointRange clamps inclusively at both boundaries.
    val range = 1.0..10.0
    println(9.9.coerceIn(range))
    println(0.0.coerceIn(range))
    println(10.0.coerceIn(range))
    println(Double.NaN.coerceIn(range).isNaN())
    val nanRange = 1.0..Double.NaN
    val reversedRange = 10.0..1.0
    println(catchesIllegalArgument { 9.9.coerceIn(nanRange) })
    println(catchesIllegalArgument { 9.9.coerceIn(reversedRange) })

    // Float uses the same inclusive and IEEE-754 empty-range semantics.
    val floatRange = 1.0f..10.0f
    println(0.0f.coerceIn(floatRange))
    println(Float.NaN.coerceIn(floatRange).isNaN())
    println(catchesIllegalArgument { 9.9f.coerceIn(1.0f..Float.NaN) })
    println(catchesIllegalArgument { 9.9f.coerceIn(10.0f..1.0f) })
}
