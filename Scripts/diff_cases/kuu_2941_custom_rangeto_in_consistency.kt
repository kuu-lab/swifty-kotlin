// KUU-2941: `x in left..right` must honor a resolved custom rangeTo and stay
// consistent with `x in range` for interface-typed ranges.
var doubleRangeToCalls = 0

operator fun Double.rangeTo(other: Double): ClosedRange<Double> {
    doubleRangeToCalls += 1
    return genericRangeTo(this, other)
}

var floatRangeToCalls = 0

operator fun Float.rangeTo(other: Float): ClosedFloatingPointRange<Float> {
    floatRangeToCalls += 1
    return object : ClosedFloatingPointRange<Float> {
        override val start: Float get() = other
        override val endInclusive: Float get() = this@rangeTo
        override fun lessThanOrEquals(a: Float, b: Float) = a <= b
    }
}

fun <T : Comparable<T>> genericRangeTo(start: T, end: T): ClosedRange<T> = start..end

fun check(x: Double, left: Double, right: Double): Boolean {
    val result = x in left..right
    val range = left..right
    if (result != (x in range)) println("MISMATCH")
    return result
}

class AlwaysEmpty(val a: Double, val b: Double) : ClosedRange<Double> {
    override val start = a
    override val endInclusive = b
    override operator fun contains(value: Double) = false
}

class LargeOnly : ClosedRange<Int> {
    override val start = 100
    override val endInclusive = 200
    override operator fun contains(value: Int) = value > 150
}

// A custom rangeTo may also return a concrete range-interface class.
class Weird(override val start: Double, override val endInclusive: Double) : ClosedRange<Double> {
    override fun isEmpty(): Boolean = start > endInclusive
}

var weirdCalls = 0

operator fun Double.rangeTo(other: Int): Weird {
    weirdCalls++
    return Weird(this, other.toDouble())
}

fun main() {
    // compareTo semantics on ComparableRange: -0.0 < 0.0, NaN == NaN.
    println(check(-0.0, 0.0, 0.0))
    println(check(0.5, 0.0, 1.0))
    println(check(1.5, 0.0, 1.0))
    println(check(Double.NaN, Double.NaN, Double.NaN))
    println("calls=$doubleRangeToCalls")
    // Inverted anonymous ClosedFloatingPointRange: never contains.
    println(0.5f in 0.0f..1.0f)
    val fr = 0.0f..1.0f
    println(0.5f in fr)
    println("fCalls=$floatRangeToCalls")
    // Custom ClosedRange implementations must dispatch their own contains.
    println(0.5 in AlwaysEmpty(0.0, 1.0))
    val empty: ClosedRange<Double> = AlwaysEmpty(0.0, 1.0)
    println(0.5 in empty)
    println(150 in LargeOnly())
    val large: ClosedRange<Int> = LargeOnly()
    println(120 in large)
    println(160 in large)
    // Concrete-class rangeTo result: the operator must actually run and the
    // inherited ClosedRange.contains must dispatch on the object.
    println(0.5 in 0.0..1)
    val wr = 0.0..1
    println(0.5 in wr)
    println(2.0 in wr)
    println("weirdCalls=$weirdCalls")
    // Built-in ranges keep their runtime-backed semantics.
    println(3 in 1..5)
    println("c" in "a".."d")
}
