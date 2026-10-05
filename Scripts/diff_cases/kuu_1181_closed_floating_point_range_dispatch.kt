fun inspect(r: ClosedFloatingPointRange<Double>) {
    println(r.start)
    println(r.endInclusive)
}

fun inspectFloat(r: ClosedFloatingPointRange<Float>) {
    println(r.start)
    println(r.endInclusive)
}

fun <T : Comparable<T>> inspectGeneric(r: ClosedFloatingPointRange<T>) {
    println(r.start)
    println(r.endInclusive)
}

fun <T : Comparable<T>> inspectClosed(r: ClosedRange<T>) {
    println(r.start)
    println(r.endInclusive)
}

fun <T : Comparable<T>> forward(r: ClosedFloatingPointRange<T>): ClosedFloatingPointRange<T> = r

fun returnedRange(): ClosedFloatingPointRange<Double> = -2.5..3.25

fun inspectNullable(r: ClosedFloatingPointRange<Double>?) {
    println(r?.start)
    println(r?.endInclusive)
    if (r != null) inspect(r)
}

open class CustomRange : ClosedFloatingPointRange<Double> {
    override val start: Double get() { println("custom start"); return -7.5 }
    override val endInclusive: Double get() { println("custom end"); return 9.25 }
    override fun lessThanOrEquals(a: Double, b: Double): Boolean = a <= b
}

class DerivedRange : CustomRange() {
    override val start: Double get() { println("derived start"); return -12.5 }
}

class CustomFloatRange : ClosedFloatingPointRange<Float> {
    override val start: Float = -4.5f
    override val endInclusive: Float = 6.25f
    override fun lessThanOrEquals(a: Float, b: Float): Boolean = a <= b
}

var receiverReads = 0
fun evaluatedOnce(r: ClosedFloatingPointRange<Double>): ClosedFloatingPointRange<Double> {
    receiverReads++
    return r
}

fun main() {
    inspect(0.0..1.0)
    inspectFloat(0.0f..1.0f)
    val doubleLocal = -0.0..1.25
    val floatLocal = -0.0f..1.25f
    inspect(doubleLocal)
    inspectFloat(floatLocal)
    inspect(returnedRange())
    inspectGeneric(forward(-0.0..0.0))
    inspectGeneric(forward(-0.0f..0.0f))
    inspectClosed(returnedRange())
    inspectClosed(-4.5f..6.25f)
    inspectNullable(returnedRange())
    inspectNullable(null)
    inspect(5.5..-2.25)
    inspect(Double.NaN..Double.POSITIVE_INFINITY)
    inspectFloat(Float.NEGATIVE_INFINITY..Float.NaN)
    inspect(CustomRange())
    inspect(DerivedRange())
    inspectGeneric(forward(DerivedRange()))
    inspectClosed(CustomRange())
    inspectFloat(CustomFloatRange())
    inspectGeneric(CustomFloatRange())
    inspectClosed(CustomFloatRange())
    println(evaluatedOnce(returnedRange()).start)
    println(evaluatedOnce(CustomRange()).endInclusive)
    println(receiverReads)
}
