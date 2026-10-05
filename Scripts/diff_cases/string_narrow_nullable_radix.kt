fun parse(value: String, radix: Int) {
    println("$value:$radix:${value.toByteOrNull(radix)}:${value.toShortOrNull(radix)}")
}

fun check(label: String, block: () -> Any?) {
    try {
        println("$label=${block()}")
    } catch (e: NumberFormatException) {
        println("$label=NFE:${e.message}")
    } catch (e: IllegalArgumentException) {
        println("$label=IAE:${e.message}")
    }
}

fun main() {
    println("7f".toShort(16))
    println("7f".toShortOrNull(16))
    println("ff".toByteOrNull(16))
    for (value in listOf("0", "-0", "+7f", "7f", "80", "-80", "-81", "ff",
        "7fff", "8000", "-8000", "-8001", "ffffffff", "", "+", "-", "gg",
        " 7f", "7f ", "1_0", "ＦＦ")) {
        parse(value, 16)
    }
    for (value in listOf("127", "128", "-128", "-129", "32767", "32768",
        "-32768", "-32769", "2147483648", "１２", "١٢")) {
        parse(value, 10)
        println(value.toByteOrNull())
        println(value.toShortOrNull())
    }
    parse("1111111", 2)
    parse("-10000000", 2)
    parse("111111111111111", 2)
    parse("-1000000000000000", 2)
    parse("z", 36)
    parse("Z", 36)
    for (base in listOf(0, 1, 37)) {
        check("byte:$base") { "1".toByteOrNull(base) }
        check("short:$base") { "1".toShortOrNull(base) }
        check("emptyByte:$base") { "".toByteOrNull(base) }
        check("emptyShort:$base") { "".toShortOrNull(base) }
        check("throwingShort:$base") { "1".toShort(base) }
    }
    check("shortMax") { "7fff".toShort(16) }
    check("shortMin") { "-8000".toShort(16) }
    check("shortOverflow") { "8000".toShort(16) }
    check("shortUnderflow") { "-8001".toShort(16) }
    check("shortInvalid") { "gg".toShort(16) }
}
