fun doubles(value: Double) {
    println(value.isNaN())
    println(value.isInfinite())
    println(value.isFinite())
}
fun floats(value: Float) {
    println(value.isNaN())
    println(value.isInfinite())
    println(value.isFinite())
}
var reads = 0
fun source(present: Boolean): Double? { reads++; return if (present) Double.POSITIVE_INFINITY else null }
fun floatSource(present: Boolean): Float? { reads++; return if (present) Float.NaN else null }
fun main() {
    doubles(Double.NaN)
    doubles(Double.POSITIVE_INFINITY)
    doubles(Double.NEGATIVE_INFINITY)
    doubles(0.0)
    doubles(-0.0)
    doubles(Double.MAX_VALUE)
    doubles(Double.MIN_VALUE)
    floats(Float.NaN)
    floats(Float.POSITIVE_INFINITY)
    floats(Float.NEGATIVE_INFINITY)
    floats(0.0f)
    floats(-0.0f)
    floats(Float.MAX_VALUE)
    floats(Float.MIN_VALUE)
    println(source(true)?.isInfinite())
    println(source(false)?.isInfinite())
    println(source(true)?.isFinite())
    println(source(false)?.isFinite())
    println(floatSource(true)?.isNaN())
    println(floatSource(false)?.isNaN())
    println(reads)
}
