fun main() {
    val reversed = reverseOrder<String>()

    println(maxOf("a", "c", reversed))
    println(maxOf("a", "b", "c", reversed))
    println(maxOf("a", "b", "c", "d", comparator = reversed))
    println(maxOf((-128).toByte(), (-1).toByte(), 0.toByte(), 127.toByte()))
    println(maxOf((-32768).toShort(), (-1).toShort(), 0.toShort(), 32767.toShort()))
    println(maxOf(1u, 4u, 2u, 3u))
    println(maxOf(1uL, 4uL, 2uL, 3uL))
    println(maxOf(1.0f, Float.NaN).isNaN())
    println(maxOf(-0.0, 0.0).toBits())
}
