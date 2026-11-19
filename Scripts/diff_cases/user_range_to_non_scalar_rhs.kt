// DIFF_JVM
class Marker { override fun toString(): String = "M" }
operator fun <T> T.rangeTo(end: Marker): String = "custom($end)"

fun main() {
    println(1..Marker())
    println(1L..Marker())
    println('a'..Marker())
    println(1.0..Marker())
    println(true..Marker())
}
