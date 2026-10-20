fun main() {
    println("7f".toByte(16)); println("32767".toShort()); println("ff".toInt(16)); println("9223372036854775807".toLong())
    println("１２".toInt()); println("-0.5".toDouble()); println("1.5".toFloat())
    println("2147483648".toIntOrNull()); println("bad".toLongOrNull()); println("128".toByteOrNull()); println("7fff".toShortOrNull(16))
    println("NaN".toDoubleOrNull()); println("bad".toFloatOrNull()); println("TRUE".toBoolean()); println("true".toBooleanStrict())
    println("TRUE".toBooleanStrictOrNull()); val missing: String? = null; println(missing.toBoolean())
    try { "1".toInt(1) } catch (e: IllegalArgumentException) { println("radix") }
    try { "overflow".toInt() } catch (e: NumberFormatException) { println("number") }
    try { "x".repeat(-1) } catch (e: IllegalArgumentException) { println("repeat") }
    try { "x".take(-1) } catch (e: IllegalArgumentException) { println("take") }
    try { println("x"[1]) } catch (e: IndexOutOfBoundsException) { println("index") }
    try { println("x".substring(2)) } catch (e: IndexOutOfBoundsException) { println("substring") }
    try { "x".split(",", limit = -1) } catch (e: IllegalArgumentException) { println("limit") }
}
