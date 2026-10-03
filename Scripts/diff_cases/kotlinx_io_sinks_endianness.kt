import kotlinx.io.*

// Sinks.kt little-endian / unsigned / floating-point writers + writeToInternalBuffer.
// Byte contents are printed so they must match kotlinc + kotlinx-io 0.9.1 exactly.

fun printBytes(buf: Buffer) {
    val out = ByteArray(buf.size.toInt())
    buf.readAtMostTo(out, 0, out.size)
    println(out.joinToString(","))
}

fun main() {
    val le = Buffer()
    le.writeShortLe(0x1234.toShort())
    le.writeIntLe(0x01020304)
    le.writeLongLe(0x0102030405060708L)
    printBytes(le)

    val un = Buffer()
    un.writeUByte(255.toUByte())
    un.writeUShort(0xABCD.toUShort())
    un.writeUInt(0xDEADBEEFu)
    un.writeULong(0x0102030405060708uL)
    un.writeUShortLe(0x1234.toUShort())
    un.writeUIntLe(0x01020304u)
    un.writeULongLe(0x0102030405060708uL)
    printBytes(un)

    val fp = Buffer()
    fp.writeFloat(1.5f)
    fp.writeDouble(2.5)
    fp.writeFloatLe(1.5f)
    fp.writeDoubleLe(2.5)
    fp.writeFloat(Float.POSITIVE_INFINITY)
    fp.writeDouble(Double.NEGATIVE_INFINITY)
    printBytes(fp)

    // writeToInternalBuffer exposes the sink's buffer to the lambda, then hintEmit()s.
    val ib = Buffer()
    ib.writeToInternalBuffer { b ->
        b.write(byteArrayOf(65, 66, 67), 0, 3)
        println(b.size)
    }
    println(ib.size)
    printBytes(ib)
}
