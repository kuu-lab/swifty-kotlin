@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val stringArray = arrayOf("a", "c", "e", "g")
    println(stringArray.binarySearch("c"))
    println(stringArray.binarySearch("d", 1))
    println(stringArray.binarySearch("g", 1, 4))

    // Generic Array natural-order search, including searching for the zero /
    // false elements that must not be confused with `null`.
    val boxedInts = arrayOf(0, 1, 2, 3)
    println(boxedInts.binarySearch(0))
    println(boxedInts.binarySearch(2))
    println(boxedInts.binarySearch(4))

    val boxedLongs = arrayOf(0L, 5L, 9L)
    println(boxedLongs.binarySearch(0L))

    val boxedDoubles = arrayOf(0.0, 1.5, 2.5)
    println(boxedDoubles.binarySearch(0.0))

    val boxedBools = arrayOf(false, true)
    println(boxedBools.binarySearch(false))
    println(boxedBools.binarySearch(true))

    // Generic Array comparator search.
    val words = arrayOf("a", "bb", "ccc")
    println(words.binarySearch("bb", naturalOrder()))
    println(words.binarySearch("z", naturalOrder()))
    println(words.binarySearch("bb", compareBy<String> { it.length }))
    val descending = arrayOf(9, 7, 5, 3, 1)
    println(descending.binarySearch(5, reverseOrder()))

    val intArray = intArrayOf(10, 20, 30, 40)
    println(intArray.binarySearch(20))
    println(intArray.binarySearch(25, 1))
    println(intArray.binarySearch(40, 1, 4))

    val longArray = longArrayOf(10L, 20L, 30L, 40L)
    println(longArray.binarySearch(30L))

    val shortArray = shortArrayOf(10, 20, 30)
    println(shortArray.binarySearch(20))

    val byteArray = byteArrayOf(10, 20, 30)
    println(byteArray.binarySearch(20))

    val charArray = charArrayOf('a', 'c', 'e')
    println(charArray.binarySearch('c'))

    val doubleArray = doubleArrayOf(1.0, 2.0, 3.0)
    println(doubleArray.binarySearch(2.0))

    val floatArray = floatArrayOf(1.0f, 2.0f, 3.0f)
    println(floatArray.binarySearch(2.0f))

    val uintArray = uintArrayOf(10u, 20u, 30u, 40u)
    println(uintArray.binarySearch(30u))
    println(uintArray.binarySearch(15u, 1))
    println(uintArray.binarySearch(40u, 1, 4))

    val ulongArray = ulongArrayOf(10uL, 20uL, 30uL, 40uL)
    println(ulongArray.binarySearch(30uL))
    println(ulongArray.binarySearch(15uL, 1))
    println(ulongArray.binarySearch(40uL, 1, 4))

    val ushortArray = ushortArrayOf(10.toUShort(), 20.toUShort(), 30.toUShort())
    println(ushortArray.binarySearch(20.toUShort()))

    val ubyteArray = ubyteArrayOf(10.toUByte(), 20.toUByte(), 30.toUByte())
    println(ubyteArray.binarySearch(20.toUByte()))
}
