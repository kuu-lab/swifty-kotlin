// Numeric parsing edge cases: signed zero for unsigned targets, non-ASCII
// decimal digits, signed NaN and trimming of only chars <= U+0020, and
// String.toLong(radix)/toLongOrNull(radix).
fun main() {
    println("-0".toUIntOrNull())
    println("-0".toULongOrNull())
    println("-00".toUByteOrNull())
    println("-0".toUShortOrNull(16))
    println("+7".toUIntOrNull())
    println("0".toULongOrNull())
    println("-0".toIntOrNull())
    println("+".toIntOrNull())
    println("".toLongOrNull())

    println("١٢٣".toIntOrNull())
    println("４２".toLongOrNull())
    println("-१०".toInt())
    println("ＡＢ".toIntOrNull(16))
    println("𝟙".toIntOrNull())
    try {
        println("١x".toInt())
    } catch (e: NumberFormatException) {
        println("NumberFormatException")
    }

    println("-NaN".toDoubleOrNull())
    println("+NaN".toFloatOrNull())
    println(" 1.5".toDoubleOrNull())
    println("1.5\u0001".toDoubleOrNull())
    println("  2".toFloatOrNull())
    println(" 1.5".toDoubleOrNull())
    println("1.5 ".toDoubleOrNull())
    println("\t\n 3.25 \r".toDouble())

    println("zz".toLong(36))
    println("ff".toLong(16))
    println("-101".toLong(2))
    println("7fffffffffffffff".toLong(16))
    println("zz".toLongOrNull(36))
    println("8000000000000000".toLongOrNull(16))
    println("-7fffffffffffffff".toLongOrNull(16))
    println("12".toLongOrNull(2))
    try {
        println("12".toLong(2))
    } catch (e: NumberFormatException) {
        println("NumberFormatException")
    }
}
