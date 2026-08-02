fun main() {
    // BUG-158: primitive arrays must honor the trailing transform lambda.
    val bytes = byteArrayOf(10, 20, 30)
    println(bytes.joinToString(",") { (it + 1).toString() })

    val ints = intArrayOf(1, 2, 3)
    println(ints.joinToString { (it * 2).toString() })
    println(ints.joinToString(",") { (it * 2).toString() })
    println(ints.joinToString(", ", "[", "]") { (it * 2).toString() })
    println(ints.joinToString())
    println(ints.joinToString(separator = "-"))

    val shorts = shortArrayOf(1, 2)
    println(shorts.joinToString(";") { (it + 1).toString() })

    val longs = longArrayOf(1L, 2L)
    println(longs.joinToString("|") { (it + 1L).toString() })

    val doubles = doubleArrayOf(1.5, 2.5)
    println(doubles.joinToString(";") { (it * 2).toString() })

    val floats = floatArrayOf(1.5f, 2.5f)
    println(floats.joinToString(";") { (it + 1.0f).toString() })

    val booleans = booleanArrayOf(true, false)
    println(booleans.joinToString(";") { it.toString() })
    println(booleans.joinToString(";") { if (it) "T" else "F" })

    val chars = charArrayOf('a', 'b')
    println(chars.joinToString(";") { it.toString() })
    println(chars.joinToString("") { "[" + it + "]" })

    val uints = uintArrayOf(1u, 2u)
    println(uints.joinToString(";") { (it + 1u).toString() })

    val ulongs = ulongArrayOf(1uL, 2uL)
    println(ulongs.joinToString(";") { (it + 1uL).toString() })
}
