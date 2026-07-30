fun main() {
    // DEBT-KIR-006: primitive arrays' joinToString(transform) used to silently
    // ignore the transform lambda and join the elements' raw toString() instead
    // (the non-transform (separator, prefix, postfix) overload was the only one
    // registered, so a trailing lambda got jammed positionally into "prefix").
    val ints = intArrayOf(1, 2, 3)
    println(ints.joinToString(",") { (it * 10).toString() })
    println(ints.joinToString { (it * 2).toString() })
    println(ints.joinToString(";") { (it * 2).toString() })
    println(ints.joinToString(";", "[") { (it * 2).toString() })
    println(ints.joinToString(";", "[", "]") { (it * 2).toString() })
    // Non-transform overload must keep working alongside the new ones.
    println(ints.joinToString())
    println(ints.joinToString(prefix = "<", postfix = ">"))
    println(ints.joinToString(separator = ":", prefix = "[", postfix = "]"))

    println(longArrayOf(1L, 2L, 3L).joinToString(",") { (it * 10).toString() })
    println(byteArrayOf(1, 2, 3).joinToString(",") { (it * 10).toString() })
    println(shortArrayOf(1, 2, 3).joinToString(",") { (it * 10).toString() })
    println(doubleArrayOf(1.0, 2.0, 3.0).joinToString(",") { (it * 10).toString() })
    println(floatArrayOf(1.0f, 2.0f, 3.0f).joinToString(",") { (it * 10).toString() })
    println(booleanArrayOf(true, false).joinToString(",") { (!it).toString() })
    println(charArrayOf('a', 'b', 'c').joinToString(",") { it.uppercaseChar().toString() })

    val u1: UInt = 1u
    val u2: UInt = 2u
    val u3: UInt = 3u
    println(uintArrayOf(u1, u2, u3).joinToString(",") { (it * 10u).toString() })
    val ul1: ULong = 1uL
    val ul2: ULong = 2uL
    val ul3: ULong = 3uL
    println(ulongArrayOf(ul1, ul2, ul3).joinToString(",") { (it * 10uL).toString() })

    val ubyteArr = UByteArray(3) { i -> (i + 1).toUByte() }
    println(ubyteArr.joinToString(",") { (it * 10u).toString() })
    val ushortArr = UShortArray(3) { i -> (i + 1).toUShort() }
    println(ushortArr.joinToString(",") { (it * 10u).toString() })

    // Original DEBT-KIR-006 repro: a List<String> receiver chained straight off
    // split(), plus a value seen only through an Iterable<T>-typed variable.
    println("a\r\nbb\r\nccc".split("\r\n").joinToString(",") { it.length.toString() })
    val iterInts: Iterable<Int> = listOf(1, 2, 3)
    println(iterInts.joinToString("-") { (it * 2).toString() })
}
