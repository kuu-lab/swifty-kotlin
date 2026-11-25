// DIFF_JVM
class Marker { override fun toString(): String = "M" }
operator fun <T> T.rangeTo(that: T): String = "same($that)"

fun main() {
    println(1..Marker())
    println(1..2)
    println(true..false)
}
