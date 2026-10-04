// Byte/Short.toString(radix) resolve and render like Int.toString(radix).
fun main() {
    println(10.toByte().toString(2))
    println(300.toShort().toString(16))
    println((-10).toByte().toString(16))
    println((-300).toShort().toString(2))
    println(Byte.MIN_VALUE.toString(36))
    try { 1.toByte().toString(1) } catch (e: IllegalArgumentException) { println(e.message) }
}
