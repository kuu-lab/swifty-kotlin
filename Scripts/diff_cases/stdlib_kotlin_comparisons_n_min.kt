import kotlin.comparisons.naturalOrder

fun main() {
    println(minOf("d", "c", "b", "a"))
    println(minOf(9.toByte(), 3.toByte(), 7.toByte(), 1.toByte()))
    println(minOf(9.toShort(), 3.toShort(), 7.toShort(), 1.toShort()))
    println(minOf(9, 3, 7, 1))
    println(minOf(9L, 3L, 7L))
    println(minOf(9u.toUByte(), 3u.toUByte(), 7u.toUByte()))
    println(minOf(9u, 3u, 7u))
    println(minOf(9uL, 3uL, 7uL))
    println(minOf(9u.toUShort(), 3u.toUShort(), 7u.toUShort()))
    println(minOf(1.0, Double.NaN, 2.0))
    println(minOf(1.0f, Float.NaN, 2.0f))
    println(1.0 / minOf(0.0, -0.0))
    println(minOf(3, 2, 1, comparator = naturalOrder()))
    println(minOf(3, 2, 1, 4, comparator = naturalOrder()))
}
