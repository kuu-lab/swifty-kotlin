fun main() {
    println((-5).toByte().coerceIn((-10).toByte(), 10.toByte()))
    println((-15).toByte().coerceAtLeast((-10).toByte()))
    println(15.toByte().coerceAtMost(10.toByte()))

    println((-5).toShort().coerceIn((-10).toShort(), 10.toShort()))
    println((-15).toShort().coerceAtLeast((-10).toShort()))
    println(15.toShort().coerceAtMost(10.toShort()))
}
