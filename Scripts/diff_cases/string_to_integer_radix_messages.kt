// NumberFormatException messages match java.lang.Integer/Long/Short/Byte
// parsing: the radix is mentioned when != 10, narrow types report range errors.
fun check(f: () -> Any) {
    try { println(f()) } catch (e: NumberFormatException) { println(e.message) }
}

fun main() {
    check { "zz".toInt(16) }
    check { "zz".toInt() }
    check { "".toInt(16) }
    check { "zz".toLong(16) }
    check { "zz".toByte(16) }
    check { "300".toByte() }
    check { "300".toByte(16) }
    check { "zz".toShort() }
    check { "99999".toShort() }
    check { "zz".toShort(16) }
    check { "99999".toShort(16) }
    check { "7f".toShort(16) }
}
