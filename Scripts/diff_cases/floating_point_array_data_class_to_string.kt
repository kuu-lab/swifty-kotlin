data class FloatingArrays(val doubles: DoubleArray, val floats: FloatArray)
data class NullableFloatingArrays(val doubles: DoubleArray?, val floats: FloatArray?)

fun main() {
    val doubles = doubleArrayOf(1.0, 2.5, -0.5, -0.0, Double.NaN, Double.POSITIVE_INFINITY, Double.MIN_VALUE)
    val floats = floatArrayOf(1.0f, 2.5f, -0.5f, -0.0f, Float.NaN, Float.NEGATIVE_INFINITY, Float.MIN_VALUE)
    println(doubles.contentToString())
    println(floats.contentToString())
    println(FloatingArrays(doubles, floats).toString())
    println(FloatingArrays(doubles, floats))
    println(NullableFloatingArrays(doubles, floats))
    println(NullableFloatingArrays(null, null))
    println(arrayOf<Any>(doubles, floats).contentDeepToString())
}
