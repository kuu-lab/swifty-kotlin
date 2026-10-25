@OptIn(kotlin.ExperimentalUnsignedTypes::class)
fun main() {
    val ints = intArrayOf(1, 2)
    val iterable: Iterable<Int> = ints.asIterable()
    println(iterable.toList())
    ints[0] = 9
    println(iterable.toList())
    println(longArrayOf(3L, 4L).asIterable().toList())
    println(shortArrayOf(5, 6).asIterable().toList())
    println(byteArrayOf(7, 8).asIterable().toList())
    println(charArrayOf('a', 'b').asIterable().toList())
    println(booleanArrayOf(true, false).asIterable().toList())
    println(doubleArrayOf(1.5, 2.5).asIterable().toList())
    println(floatArrayOf(3.5f, 4.5f).asIterable().toList())
    println(ubyteArrayOf(1u, 2u).asIterable().toList())
    println(ushortArrayOf(3u, 4u).asIterable().toList())
    println(uintArrayOf(5u, 6u).asIterable().toList())
    println(ulongArrayOf(7uL, 8uL).asIterable().toList())
}
