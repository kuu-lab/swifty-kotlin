fun check(label: String, block: () -> Any) {
    try {
        println("$label=${block()}")
    } catch (e: NumberFormatException) {
        println("$label=NFE:${e.message}")
    } catch (e: IllegalArgumentException) {
        println("$label=IAE:${e.message}")
    }
}

fun decimal(value: String) {
    check("UByte:$value") { value.toUByte() }
    check("UShort:$value") { value.toUShort() }
    check("UInt:$value") { value.toUInt() }
    check("ULong:$value") { value.toULong() }
}

fun radix(value: String, radix: Int) {
    check("UByte:$value:$radix") { value.toUByte(radix) }
    check("UShort:$value:$radix") { value.toUShort(radix) }
    check("UInt:$value:$radix") { value.toUInt(radix) }
    check("ULong:$value:$radix") { value.toULong(radix) }
}

fun main() {
    for (value in listOf("0", "+1", "255", "256", "65535", "65536",
        "4294967295", "4294967296", "9223372036854775808",
        "18446744073709551615", "18446744073709551616",
        "-0", "-1", "", "+", " 1", "1 ", "1_0", "x", "１２", "١٢")) {
        decimal(value)
        radix(value, 10)
    }
    for (value in listOf("ff", "+ff", "100", "ffff", "10000", "ffffffff",
        "100000000", "8000000000000000", "ffffffffffffffff",
        "10000000000000000", "-ff", "g", "ＦＦ")) {
        radix(value, 16)
    }
    radix("11111111", 2)
    radix("z", 36)
    radix("Z", 36)
    for (base in listOf(0, 1, 37)) {
        radix("1", base)
        radix("", base)
    }
    val ubyte: UByte = "255".toUByte()
    val ushort: UShort = "ffff".toUShort(16)
    val uint: UInt = "4294967295".toUInt()
    val ulong: ULong = "8000000000000000".toULong(16)
    println(ubyte.toInt())
    println(ushort.toInt())
    println(uint.toLong())
    println(ulong == 9223372036854775808uL)
    println("18446744073709551615".toULong() == 18446744073709551615uL)
    println("ffffffffffffffff".toULong(16) == 18446744073709551615uL)
}
