import kotlinx.io.*

fun decode(bytes: ByteArray) {
    val buffer = Buffer()
    buffer.write(bytes, 0, bytes.size)
    val decoded = buffer.readString()
    var i = 0
    while (i < decoded.length) {
        println(decoded[i].code)
        i += 1
    }
    println("end")
}

fun main() {
    decode(byteArrayOf(0x80.toByte(), 0xff.toByte(), 65))
    decode(byteArrayOf(0xc0.toByte(), 0x80.toByte(), 0xc2.toByte(), 65))
    decode(byteArrayOf(0xe0.toByte(), 0x80.toByte(), 0x80.toByte()))
    decode(byteArrayOf(0xed.toByte(), 0xa0.toByte(), 0x80.toByte()))
    decode(byteArrayOf(0xf0.toByte(), 0x80.toByte(), 0x80.toByte(), 0x80.toByte()))
    decode(byteArrayOf(0xf4.toByte(), 0x90.toByte(), 0x80.toByte(), 0x80.toByte()))
    decode(byteArrayOf(0xc2.toByte()))
    decode(byteArrayOf(0xe2.toByte(), 0x82.toByte()))
    decode(byteArrayOf(0xf0.toByte(), 0x9f.toByte(), 0x98.toByte()))
    decode(byteArrayOf(0xe2.toByte(), 0x82.toByte(), 65))
    decode(byteArrayOf(0xf0.toByte(), 0x9f.toByte(), 65, 0x80.toByte()))
    decode(byteArrayOf(0xf0.toByte(), 0x9f.toByte(), 0x98.toByte(), 0x80.toByte()))

    val buffer = Buffer()
    buffer.write(byteArrayOf(0xe2.toByte(), 0x82.toByte()), 0, 2)
    try { buffer.readCodePointValue() } catch (e: EOFException) { println(buffer.size) }
    buffer.writeByte(65)
    println(buffer.readCodePointValue())
    println(buffer.size)
    println(buffer.readCodePointValue())
    buffer.writeString("€")
    println(buffer.readString(2L))
    println(buffer.readString())
}
