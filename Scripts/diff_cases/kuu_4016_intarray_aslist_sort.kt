// KUU-4016: IntArray.asList() leaked raw words to generic consumers, crashing
// Comparable-driven sort()/sorted(). The same omission existed for Byte/Short
// and the unsigned value-class arrays.
@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    // The original ticket reproduction.
    println(intArrayOf(3, 1).asList().sorted())
    println(intArrayOf(3, 1).asList().sortedDescending())
    val ints = intArrayOf(3, 1).asList().toMutableList()
    ints.sort()
    println(ints)
    println(intArrayOf(3, 1).asList().toList().sorted())
    println(intArrayOf(3, 1).toList().sorted())
    println(intArrayOf(3, 1).asList().toSet().sorted())

    // Elements must answer `is`/Comparable through generic boundaries.
    val intView = intArrayOf(3, 1).asList()
    println((intView[0] as Any) is Int)
    println(intView == listOf(3, 1))
    println(intView.asReversed())

    // The same view for the sibling signed integer arrays.
    println(byteArrayOf(3, 1).asList().sorted())
    println(shortArrayOf(3, 1).asList().sorted())
    println(byteArrayOf(3, 1).toList().sorted())
    println(shortArrayOf(3, 1).toList().sorted())

    // The unsigned value classes share the signed storage and got the same
    // fix; unsigned payloads must render/compare zero-extended.
    println(ubyteArrayOf(200u, 1u).asList())
    println(ubyteArrayOf(3u, 1u).asList().sorted())
    println(ushortArrayOf(52505u, 1u).asList())
    println(ushortArrayOf(3u, 1u).asList().sorted())
    println(uintArrayOf(4294967295u, 1u).asList())
    println(uintArrayOf(3u, 1u).asList().sorted())
    println(ulongArrayOf(18446744073709551615uL, 1uL).asList())
    println(ulongArrayOf(3uL, 1uL).asList().sorted())
}
