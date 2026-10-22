// DIFF_JVM
fun matchesMask(x: Long): Boolean = (x and 3) == 0L

fun main() {
    val value = 0x1234L
    println(matchesMask(0x1230L))
    println(matchesMask(value))
    println(value and 0xFF)
    println(value or 3)
    println(value xor 3)
    println(1L shl 56)
}
