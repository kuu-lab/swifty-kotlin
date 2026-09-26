import kotlinx.io.*

// Exercises Buffer's core read/write surface (primitives, ByteArray, get,
// indexOf, copy, toString) without any upstream RawSource/RawSink.

fun main() {
    val buf = Buffer()
    println(buf.size)
    println(buf.exhausted())

    buf.writeByte(0x41)
    buf.writeShort(0x1234)
    buf.writeInt(0x0102_0304)
    buf.writeLong(0x0A0B_0C0D_0E0F_1011L)
    println(buf.size)

    println(buf.readByte())
    println(buf.readShort())
    println(buf.readInt())
    println(buf.readLong())
    println(buf.exhausted())

    val bytes = byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8)
    buf.write(bytes, 0, bytes.size)
    println(buf.size)
    println(buf.get(0L))
    println(buf.get(7L))
    println(buf.indexOf(5))
    println(buf.indexOf(99))

    val out = ByteArray(4)
    val n = buf.readAtMostTo(out, 0, out.size)
    println(n)
    println(out.joinToString(","))
    println(buf.size)

    val copy = buf.copy()
    buf.clear()
    println(buf.size)
    println(copy.size)
    println(copy.readAtMostTo(ByteArray(4), 0, 4))

    val other = Buffer()
    other.writeByte(9)
    other.writeByte(10)
    other.copyTo(copy)
    println(copy.size)

    val hexBuf = Buffer()
    hexBuf.writeByte(0x00)
    hexBuf.writeByte(0xFF.toByte())
    println(hexBuf.toString())
    println(Buffer().toString())
}
