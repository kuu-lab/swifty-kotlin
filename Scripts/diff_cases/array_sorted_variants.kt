@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    // Generic Array natural-order sorting.
    val ints = arrayOf(3, 1, 4, 1, 5, 9, 2, 6, 0)
    println(ints.sortedArray().joinToString(","))
    println(ints.sortedArrayDescending().joinToString(","))

    val words = arrayOf("banana", "apple", "cherry", "date")
    println(words.sortedArray().joinToString(","))
    println(words.sortedArrayDescending().joinToString(","))

    // sortedArrayWith comparator overloads.
    println(words.sortedArrayWith(naturalOrder()).joinToString(","))
    println(words.sortedArrayWith(reverseOrder()).joinToString(","))
    println(words.sortedArrayWith(compareBy<String> { it.length }).joinToString(","))
    println(words.sortedArrayWith(compareByDescending<String> { it.length }).joinToString(","))

    // Stability: elements that compare equal keep their original order.
    val pairs = arrayOf("b2", "a1", "a2", "b1")
    println(pairs.sortedArrayWith(compareBy<String> { it[0] }).joinToString(","))

    // Primitive arrays.
    println(intArrayOf(5, 3, 4, 1, 2, 0).sortedArray().joinToString(","))
    println(intArrayOf(5, 3, 4, 1, 2, 0).sortedArrayDescending().joinToString(","))
    println(longArrayOf(5L, 3L, 4L, 1L).sortedArray().joinToString(","))
    println(shortArrayOf(5, 3, 4, 1).sortedArray().joinToString(","))
    println(byteArrayOf(5, 3, 4, 1).sortedArray().joinToString(","))
    println(charArrayOf('e', 'c', 'a', 'd', 'b').sortedArray().joinToString(","))
    println(doubleArrayOf(2.5, 1.5, 3.5, 0.5).sortedArray().joinToString(","))
    println(floatArrayOf(2.5f, 1.5f, 3.5f, 0.5f).sortedArray().joinToString(","))
    println(uintArrayOf(5u, 3u, 4u, 1u).sortedArray().joinToString(","))
    println(ulongArrayOf(5uL, 3uL, 4uL, 1uL).sortedArray().joinToString(","))

    // Floating-point total order: NaN sorts last.
    val doubles = doubleArrayOf(3.0, Double.NaN, 1.0, -1.0, 2.0)
    println(doubles.sortedArray().joinToString(",") { it.toString() })
    val floats = floatArrayOf(3.0f, Float.NaN, 1.0f, -1.0f, 2.0f)
    println(floats.sortedArray().joinToString(",") { it.toString() })
}
