fun <T> eq(a: T, b: T): Boolean = a == b

fun main() {
    println(eq(0, 0L))
    println(eq(0, Float.MIN_VALUE.toLong()))
    val value: Long = 0
    println(eq(0, value))
}
