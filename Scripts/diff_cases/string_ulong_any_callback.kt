// KUU-1982: parsed ULong values retain their unsigned identity at Any return boundaries.
fun show(value: Any?) {
    println("$value:${value is ULong}")
}

fun callback(block: () -> Any) { show(block()) }
fun nullableCallback(block: () -> Any?) { show(block()) }

fun inspect(text: String, radix: Int, expected: ULong) {
    val parsed = text.toULong(radix)
    println(parsed == expected)
    val any: Any = parsed
    val nullableAny: Any? = parsed
    show(any)
    show(nullableAny)
    callback { text.toULong(radix) }
    nullableCallback { text.toULong(radix) }
    callback { return@callback text.toULong(radix) }
    val stored: () -> Any = { text.toULong(radix) }
    val storedNullable: () -> Any? = { text.toULongOrNull(radix) }
    show(stored())
    show(storedNullable())
}

fun main() {
    inspect("9223372036854775808", 10, 9223372036854775808uL)
    inspect("18446744073709551615", 10, 18446744073709551615uL)
    inspect("8000000000000000", 16, 9223372036854775808uL)
    inspect("ffffffffffffffff", 16, 18446744073709551615uL)
    callback { "9223372036854775808".toULong() }
    callback { "18446744073709551615".toULong() }
    nullableCallback { "9223372036854775808".toULongOrNull() }
    nullableCallback { "18446744073709551615".toULongOrNull() }
    nullableCallback { "invalid".toULongOrNull() }
    nullableCallback { null }
    try {
        callback { "18446744073709551616".toULong() }
    } catch (e: NumberFormatException) {
        println("NFE:${e.message}")
    }
    try {
        callback { "1".toULong(1) }
    } catch (e: IllegalArgumentException) {
        println("IAE:${e.message}")
    }
}
