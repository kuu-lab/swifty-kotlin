// KUU-2386: synthesized hashCode must preserve signed zero and canonicalize NaN.
data class DoubleHashValue(val x: Double)
data class DoubleHashPair(val x: Double, val y: Int)

fun main() {
    println(DoubleHashValue(+0.0).hashCode())
    println(DoubleHashValue(-0.0).hashCode())
    println((+0.0).hashCode() != (-0.0).hashCode())
    println(DoubleHashValue(+0.0) != DoubleHashValue(-0.0))
    println(DoubleHashValue(1.5).hashCode())
    println(DoubleHashValue(-2.5).hashCode())
    println(DoubleHashPair(-0.0, 7).hashCode())
    val nan = Double.fromBits(0x7ff0000000000001L)
    println(DoubleHashValue(nan).hashCode())
    println(DoubleHashValue(Double.NaN).hashCode() == DoubleHashValue(nan).hashCode())
    println(DoubleHashValue(Double.NaN) == DoubleHashValue(Double.NaN))
    val values = hashSetOf(DoubleHashValue(+0.0), DoubleHashValue(-0.0), DoubleHashValue(Double.NaN), DoubleHashValue(Double.NaN))
    println(values.size)
    println(values.contains(DoubleHashValue(-0.0)))
    println(values.contains(DoubleHashValue(Double.NaN)))
}
