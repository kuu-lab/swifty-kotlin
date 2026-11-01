// KUU-4025: bundled hex API parity — Short/Byte and unsigned toHexString
// variants plus String.hexToByte.
fun main() {
    // Signed small receivers: fixed-width two's-complement digits.
    println(255.toShort().toHexString()) // 00ff
    println(255.toByte().toHexString()) // ff
    println((-1).toShort().toHexString()) // ffff
    println((-1).toByte().toHexString()) // ff
    println(0.toByte().toHexString()) // 00

    // Unsigned receivers.
    println(255u.toHexString()) // 000000ff
    println(255uL.toHexString()) // 00000000000000ff
    println(255.toUByte().toHexString()) // ff
    println(65535.toUShort().toHexString()) // ffff
    println(UInt.MAX_VALUE.toHexString()) // ffffffff
    println(ULong.MAX_VALUE.toHexString()) // ffffffffffffffff
    println(0u.toHexString()) // 00000000

    // NumberHexFormat options apply to the new receivers too.
    println(255.toByte().toHexString(HexFormat.UpperCase)) // FF
    val fmt = HexFormat { number { prefix = "0x"; removeLeadingZeros = true } }
    println(255.toShort().toHexString(fmt)) // 0xff
    println(255.toByte().toHexString(fmt)) // 0xff
    println(255u.toHexString(fmt)) // 0xff
    println(0.toUByte().toHexString(fmt)) // 0x0
    val padded = HexFormat { number { removeLeadingZeros = true; minLength = 4 } }
    println(255.toByte().toHexString(padded)) // 00ff
    println(255.toUShort().toHexString(padded)) // ffff

    // String.hexToByte rounds out the parser family.
    println("ff".hexToByte()) // -1
    println("80".hexToByte()) // -128
    println("ff".hexToByte().toHexString()) // ff
    println("ffffffff".hexToUInt().toHexString()) // ffffffff
}
