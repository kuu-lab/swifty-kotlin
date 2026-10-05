// KUU-1185: Infinity must survive arithmetic; undefined results must throw.
import kotlin.time.Duration
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

fun printDurationResult(label: String, operation: () -> Duration) {
    try {
        val result = operation()
        println("$label=$result/${result.isInfinite()}")
    } catch (e: IllegalArgumentException) {
        println("$label=IllegalArgumentException: ${e.message}")
    }
}

fun main() {
    val negative = Duration.parse("-Infinity")
    val positive = Duration.parse("Infinity")
    println(negative + 1.seconds)
    println(negative == -Duration.INFINITE)
    println(positive == Duration.INFINITE)

    val infinities = listOf(negative, positive, -Duration.INFINITE, Duration.INFINITE)
    val finite = listOf(0.seconds, 1.nanoseconds, (-1).nanoseconds,
        1.seconds, (-1).seconds, Long.MAX_VALUE.nanoseconds, Long.MIN_VALUE.nanoseconds,
        4_611_686_018_427_387_902L.milliseconds, (-4_611_686_018_427_387_902L).milliseconds)
    for (infinity in infinities) {
        println(-infinity)
        println(infinity.absoluteValue)
        for (value in finite) {
            printDurationResult("$infinity + $value") { infinity + value }
            printDurationResult("$value + $infinity") { value + infinity }
            printDurationResult("$infinity - $value") { infinity - value }
            printDurationResult("$value - $infinity") { value - infinity }
            println("ratio=$infinity/$value=${infinity / value}")
            println("ratio=$value/$infinity=${value / infinity}")
        }
        for (other in infinities) {
            printDurationResult("$infinity + $other") { infinity + other }
            printDurationResult("$infinity - $other") { infinity - other }
            println("ratio=$infinity/$other=${infinity / other}")
        }
    }

    val durations = listOf(negative, positive, (-1).seconds, 0.seconds, 1.seconds)
    for (duration in durations) {
        for (scale in listOf(Int.MIN_VALUE, -2, -1, 0, 1, 2, Int.MAX_VALUE)) {
            printDurationResult("$duration * Int($scale)") { duration * scale }
            printDurationResult("$duration / Int($scale)") { duration / scale }
        }
        for (scale in listOf(Double.NEGATIVE_INFINITY, -2.5, -1.0, -0.0, 0.0,
            0.5, 2.5, Double.POSITIVE_INFINITY, Double.NaN)) {
            printDurationResult("$duration * Double($scale)") { duration * scale }
            printDurationResult("$duration / Double($scale)") { duration / scale }
        }
    }
}
