// KUU-763: ClosedFloatingPointRange contains/isEmpty/lessThanOrEquals on
// interface-typed receivers — runtime boxes take the floating-range bridge,
// user-defined implementations dispatch through the itable to the source
// bodies/declared overrides.

fun paramContains(range: ClosedFloatingPointRange<Double>, value: Double): Boolean =
    range.contains(value)

fun paramIsEmpty(range: ClosedFloatingPointRange<Double>): Boolean =
    range.isEmpty()

fun paramLte(range: ClosedFloatingPointRange<Double>, a: Double, b: Double): Boolean =
    range.lessThanOrEquals(a, b)

fun paramContainsF(range: ClosedFloatingPointRange<Float>, value: Float): Boolean =
    range.contains(value)

class CustomDoubleRange : ClosedFloatingPointRange<Double> {
    override val start: Double get() = 10.0
    override val endInclusive: Double get() = 20.0
    override fun lessThanOrEquals(a: Double, b: Double): Boolean = a <= b
}

fun main() {
    val range: ClosedFloatingPointRange<Double> = 1.0..2.0
    println(range.contains(1.5))
    println(range.contains(2.5))
    println(range.isEmpty())
    println(1.5 in range)
    println(2.5 in range)
    println(range.lessThanOrEquals(1.0, 2.0))
    println(range.lessThanOrEquals(2.0, 1.0))
    println(range.lessThanOrEquals(Double.NaN, 1.0))
    println(paramContains(range, 1.5))
    println(paramContains(1.0..2.0, 3.5))
    println(paramIsEmpty(range))
    println(paramIsEmpty(2.0..1.0))
    println(paramLte(range, 1.0, 1.5))
    println(paramContainsF(1.0f..2.0f, 1.5f))

    val custom: ClosedFloatingPointRange<Double> = CustomDoubleRange()
    println(custom.contains(15.0))
    println(custom.contains(25.0))
    println(custom.isEmpty())
    println(custom.lessThanOrEquals(5.0, 4.0))
    println(15.0 in custom)
    println(25.0 in custom)
}
