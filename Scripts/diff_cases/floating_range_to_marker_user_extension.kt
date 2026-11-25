// DIFF_JVM
class Marker { override fun toString(): String = "M" }
operator fun <T> T.rangeTo(end: Marker): String = "marker($end)"

fun nothingDoubleRange(): String = 1.0..error("stop")
fun nothingFloatRange(): String = 1.0f..error("stop")

fun main() {
    println(1.0..Marker())
    println(1.0f..Marker())
}
