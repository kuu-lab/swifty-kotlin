// KUU-1314: non-null primitive identity uses value equality on Kotlin/JVM.
fun compareDoubles(a: Double, b: Double) {
    println(a === b)
    println(a !== b)
}
fun compareFloats(a: Float, b: Float) {
    println(a === b)
    println(a !== b)
}
fun compareInts(a: Int, b: Int) {
    println(a === b)
    println(a !== b)
}
fun compareNullableDoubles(a: Double?, b: Double?) {
    println(a === b)
    println(a !== b)
}
fun compareAny(a: Any, b: Any) {
    println(a === b)
    println(a !== b)
}
fun main() {
    println(0.0 === -0.0)
    println(-0.0 === -0.0)
    println(1.0 === 1.0)
    println(Double.NaN === Double.NaN)
    println(1000 === 1000)
    println(127 === 127)
    compareDoubles(0.0, -0.0)
    compareDoubles(Double.NaN, Double.NaN)
    compareDoubles(1.0, 1.0)
    compareDoubles(1.0, 2.0)
    compareFloats(0.0f, -0.0f)
    compareFloats(Float.NaN, Float.NaN)
    compareFloats(1.0f, 1.0f)
    compareFloats(1.0f, 2.0f)
    compareInts(1000, 1000)
    compareInts(127, 127)
    compareInts(127, 128)
    compareNullableDoubles(null, null)
    compareNullableDoubles(null, 0.0)
    compareNullableDoubles(1.0, 1.0)
    compareNullableDoubles(0.0, -0.0)
    compareAny(1.0, 1.0)
    val boxed: Double? = 1.0
    compareNullableDoubles(boxed, boxed)
    val erased: Any = 1.0
    compareAny(erased, erased)
}
