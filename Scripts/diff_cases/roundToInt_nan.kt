import kotlin.math.roundToInt
import kotlin.math.roundToLong

fun main() {
    // Double NaN → IllegalArgumentException (Kotlin spec)
    try {
        println(Double.NaN.roundToInt())
    } catch (e: IllegalArgumentException) {
        println("caught: ${e.message}")
    }

    try {
        println(Double.NaN.roundToLong())
    } catch (e: IllegalArgumentException) {
        println("caught: ${e.message}")
    }

    // Float NaN → IllegalArgumentException (Kotlin spec)
    try {
        println(Float.NaN.roundToInt())
    } catch (e: IllegalArgumentException) {
        println("caught: ${e.message}")
    }

    try {
        println(Float.NaN.roundToLong())
    } catch (e: IllegalArgumentException) {
        println("caught: ${e.message}")
    }

    // ±Inf saturation — Kotlin spec: returns MIN/MAX, no exception
    println(Double.POSITIVE_INFINITY.roundToInt())
    println(Double.NEGATIVE_INFINITY.roundToInt())
    println(Double.POSITIVE_INFINITY.roundToLong())
    println(Double.NEGATIVE_INFINITY.roundToLong())
}
