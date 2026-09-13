fun main() {
    // KSP-1534/1535: UByte/UShort have no toChar() member in real Kotlin.
    // The correct idioms are toInt().toChar() and, for UShort, the
    // Char(UShort) constructor.
    val ub: UByte = 65u
    val us: UShort = 65u
    println(ub.toInt().toChar())
    println(us.toInt().toChar())
    println(Char(us))

    val maxUByte = UByte.MAX_VALUE
    val maxUShort = UShort.MAX_VALUE
    println(maxUByte.toInt().toChar().code)
    println(maxUShort.toInt().toChar().code)
    println(Char(maxUShort).code)

    val minUByte = UByte.MIN_VALUE
    val minUShort = UShort.MIN_VALUE
    println(minUByte.toInt().toChar().code)
    println(minUShort.toInt().toChar().code)
}
