// DIFF_JVM: KUU-2853 checks array utility calls against the JVM bundled stdlib.
fun main() {
    println(intArrayOf(3, 1, 2).contentToString())
    println(intArrayOf(1, 2).contentEquals(intArrayOf(1, 2)))
    println(intArrayOf(3, 1, 2).sortedArray().contentToString())
    println(intArrayOf(1, 2, 3).binarySearch(2))
    val values = intArrayOf(3, 1, 2)
    values.sort()
    println(values.contentToString())
    println(intArrayOf(3, 1, 2).sortedArrayDescending().contentToString())
    println(intArrayOf(1, 2, 3).reversedArray().contentToString())
    println(intArrayOf(1, 2, 3).contentHashCode())

    val words = arrayOf("z", "a", "m")
    println(words.contentToString())
    println(words.sortedArray().contentToString())
    println(words.sortedArrayDescending().contentToString())
    println(arrayOf("a", "m", "z").binarySearch("m"))
    println(arrayOf(1, 2, 3).reversedArray().contentToString())

    println(byteArrayOf(3, 1, 2).sortedArray().contentToString())
    val longValues = longArrayOf(3L, 1L, 2L)
    longValues.sort(1, 3)
    println(longValues.contentToString())
    println(charArrayOf('c', 'a', 'b').reversedArray().contentToString())
    println(booleanArrayOf(true, false).reversedArray().contentToString())

    val nested: Array<Any> = arrayOf(arrayOf(1, 2), intArrayOf(3, 4))
    val equalNested: Array<Any> = arrayOf(arrayOf(1, 2), intArrayOf(3, 4))
    println(nested.contentDeepToString())
    println(nested.contentDeepEquals(equalNested))
    println(nested.contentDeepHashCode() == equalNested.contentDeepHashCode())

    println(floatArrayOf(-0.0f, 2.0f).sortedArray().contentToString())
    println(floatArrayOf(Float.NaN).contentEquals(floatArrayOf(Float.NaN)))
    println(floatArrayOf(-0.0f).contentEquals(floatArrayOf(0.0f)))
    val missing: IntArray? = null
    println(missing.contentToString())
    println(missing.contentHashCode())
    println(missing.contentEquals(null))

    val unsigned = uintArrayOf(UInt.MAX_VALUE, 1u, 0u)
    val sortedUnsigned = unsigned.sortedArray()
    println(sortedUnsigned.contentToString())
    println(sortedUnsigned.binarySearch(UInt.MAX_VALUE))
    println(unsigned.reversedArray().contentToString())
}
