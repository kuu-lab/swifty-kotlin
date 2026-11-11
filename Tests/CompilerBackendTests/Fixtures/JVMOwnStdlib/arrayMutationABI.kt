fun main() {
    val ints = intArrayOf(0, 1, 2, 3, 4)
    check(ints.copyInto(ints, destinationOffset = 1, endIndex = 4) === ints)
    ints.fill(8, fromIndex = 3)
    check(ints.contentEquals(intArrayOf(0, 0, 1, 8, 8)))

    val longs = longArrayOf(0L, 1L, 2L)
    longs.fill(4L)
    check(longs.copyInto(LongArray(2), startIndex = 1).contentEquals(longArrayOf(4L, 4L)))

    val words = arrayOf<String?>("head", "middle", "tail")
    words.fill(null, toIndex = 1)
    val output = arrayOfNulls<String>(3)
    words.copyInto(output, destinationOffset = 1, startIndex = 1)
    check(output.contentEquals(arrayOf(null, "middle", "tail")))

    try {
        ints.fill(1, fromIndex = 3, toIndex = 2)
        error("reversed range accepted")
    } catch (_: IllegalArgumentException) {}
    println("ok")
}
