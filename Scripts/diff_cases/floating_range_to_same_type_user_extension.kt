// DIFF_JVM
operator fun <T> T.rangeTo(that: T): String = "same($that)"

fun doubleRange(): String = 1.0..2.0
fun floatRange(): String = 1.0f..2.0f
fun nothingDoubleRange(): String = 1.0..error("stop")
fun nothingFloatRange(): String = 1.0f..error("stop")

fun main() {
    println(doubleRange())
    println(floatRange())
    println(1..2)
    println('a'..'c')
    println(true..false)
}
