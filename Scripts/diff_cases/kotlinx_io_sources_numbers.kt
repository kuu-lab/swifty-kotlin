import kotlinx.io.*

class NumberChunks(private val bytes: ByteArray) : RawSource {
    private var position = 0
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (position == bytes.size) return -1L
        sink.writeByte(bytes[position])
        position += 1
        return 1L
    }
    override fun close() {}
}

fun decimal(text: String, chunked: Boolean) {
    val buffer = Buffer()
    buffer.write(text.encodeToByteArray())
    val source: Source = if (chunked) NumberChunks(text.encodeToByteArray()).buffered() else buffer
    try {
        println(source.readDecimalLong())
    } catch (e: NumberFormatException) {
        println("number:${e.message}")
    } catch (e: EOFException) {
        println("eof")
    }
    println(source.readByteArray().decodeToString())
}

fun hexadecimal(text: String, chunked: Boolean) {
    val buffer = Buffer()
    buffer.write(text.encodeToByteArray())
    val source: Source = if (chunked) NumberChunks(text.encodeToByteArray()).buffered() else buffer
    try {
        println(source.readHexadecimalUnsignedLong())
    } catch (e: NumberFormatException) {
        println("number:${e.message}")
    } catch (e: EOFException) {
        println("eof")
    }
    println(source.readByteArray().decodeToString())
}

fun main() {
    for (chunked in listOf(false, true)) {
        for (text in listOf("0!", "-0!", "0000123;", "-42;", "9223372036854775807!",
            "-9223372036854775808!", "9223372036854775808!", "-9223372036854775809!",
            "999999999999999999999", "+1", "x", "-x", "-", "")) {
            decimal(text, chunked)
        }
        for (text in listOf("0!", "aBcD;", "7fffffffffffffff", "8000000000000000!",
            "ffffffffffffffff!", "00000000000000000F;", "10000000000000000!",
            "FFFFFFFFFFFFFFFFF!", "0x12", "-1", "g", "")) {
            hexadecimal(text, chunked)
        }
    }
}
