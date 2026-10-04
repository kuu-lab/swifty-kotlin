import kotlinx.io.*

// Sink.writeDecimalLong / writeHexadecimalUnsignedLong (Sinks.kt extensions): digit-width
// boundaries, negatives, and Long.MIN_VALUE. Output must match kotlinc + kotlinx-io 0.9.1.

fun drain(buf: Buffer): String {
    val out = ByteArray(buf.size.toInt())
    buf.readAtMostTo(out, 0, out.size)
    return String(out)
}

fun main() {
    val decimals = longArrayOf(
        0L, 1L, 9L, 10L, 99L, 100L, 99999999L, 100000000L, 123456789L,
        -1L, -9L, -10L, -12345L,
        9223372036854775807L, -9223372036854775807L, Long.MIN_VALUE,
    )
    for (v in decimals) {
        val buf = Buffer()
        buf.writeDecimalLong(v)
        println(drain(buf))
    }

    val hexes = longArrayOf(
        0L, 1L, 15L, 16L, 255L, 256L, 4095L, 4096L,
        0x7fffffffL, 0x80000000L, 0xffffffffL, 0x100000000L,
        -1L, Long.MIN_VALUE, Long.MAX_VALUE,
    )
    for (v in hexes) {
        val buf = Buffer()
        buf.writeHexadecimalUnsignedLong(v)
        println(drain(buf))
    }

    // Sink.write(RawSource, byteCount) + Source.transferTo, already interface members.
    val src = Buffer()
    src.writeDecimalLong(777L)
    val dst = Buffer()
    dst.write(src, 2L)
    println(drain(dst))
    println(src.transferTo(dst))
    println(drain(dst))
}
