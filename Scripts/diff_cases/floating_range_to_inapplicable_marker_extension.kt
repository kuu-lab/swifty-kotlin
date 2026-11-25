class Marker { override fun toString(): String = "M" }
operator fun <T> T.rangeTo(end: Marker): String = "marker($end)"

fun doubleRange(): ClosedFloatingPointRange<Double> = 1.0..2.0
fun floatRange(): ClosedFloatingPointRange<Float> = 1.0f..2.0f

fun main() {
    println("ok")
}
