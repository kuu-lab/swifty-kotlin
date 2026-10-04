@OptIn(ExperimentalStdlibApi::class)
fun main() {
    // Long.toHexString zero-pads to 16 digits, matching Int's 8-digit padding.
    println(255L.toHexString())
    println(0L.toHexString())
    println((-1L).toHexString())
    println(4096L.toHexString())

    // ByteArray.toHexString / hexToByteArray round trip (default format).
    val bytes = byteArrayOf(0xDE.toByte(), 0xAD.toByte(), 0xBE.toByte(), 0xEF.toByte())
    val hex = bytes.toHexString()
    println(hex)
    println(hex.hexToByteArray().contentToString() == bytes.contentToString())

    // hexToUByte/UShort/UInt/ULong basic decode.
    println("ff".hexToUByte())
    println("ffff".hexToUShort())
    println("ffffffff".hexToUInt())
    println("ffffffffffffffff".hexToULong())

    // hexToShort / hexToLong round trip through toHexString.
    println("ffff".hexToShort().toInt())
    println((-1L).toHexString().hexToLong())
}
