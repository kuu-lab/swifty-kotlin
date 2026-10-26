@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package java.io

public open class DataInputStream(private val input: InputStream) : InputStream {
    public override fun read(): Int = input.read()

    public override fun read(buffer: ByteArray): Int = input.read(buffer)

    public override fun read(buffer: ByteArray, offset: Int, length: Int): Int = input.read(buffer, offset, length)

    public override fun available(): Int = input.available()

    public override fun skip(count: Int): Int = input.skip(count)

    public override fun mark(readLimit: Int): Unit = input.mark(readLimit)

    public override fun reset(): Unit = input.reset()

    public override fun markSupported(): Boolean = input.markSupported()

    public override fun readBytes(): ByteArray = input.readBytes()

    public override fun close(): Unit = input.close()

    public fun readBoolean(): Boolean = readUnsignedByte() != 0

    public fun readByte(): Byte = readUnsignedByte().toByte()

    public fun readUnsignedByte(): Int {
        val value = input.read()
        if (value < 0) throw EOFException()
        return value
    }

    public fun readShort(): Short = readUnsignedShort().toShort()

    public fun readUnsignedShort(): Int = (readUnsignedByte() shl 8) or readUnsignedByte()

    public fun readChar(): Char = readUnsignedShort().toChar()

    public fun readInt(): Int =
        (readUnsignedByte() shl 24) or
            (readUnsignedByte() shl 16) or
            (readUnsignedByte() shl 8) or
            readUnsignedByte()

    public fun readLong(): Long =
        (readInt().toLong() shl 32) or (readInt().toLong() and 0xffffffffL)

    public fun readFloat(): Float = Float.fromBits(readInt())

    public fun readDouble(): Double = Double.fromBits(readLong())

    public fun readUTF(): String {
        val byteCount = readUnsignedShort()
        var consumed = 0
        var result = ""
        while (consumed < byteCount) {
            val first = readUnsignedByte()
            consumed += 1
            when {
                (first and 0x80) == 0 -> result += first.toChar()
                (first and 0xe0) == 0xc0 -> {
                    val second = readUnsignedByte()
                    consumed += 1
                    result += (((first and 0x1f) shl 6) or (second and 0x3f)).toChar()
                }
                else -> {
                    val second = readUnsignedByte()
                    val third = readUnsignedByte()
                    consumed += 2
                    result += (((first and 0x0f) shl 12) or ((second and 0x3f) shl 6) or (third and 0x3f)).toChar()
                }
            }
        }
        return result
    }

    public fun readFully(buffer: ByteArray): Unit = readFully(buffer, 0, buffer.size)

    public fun readFully(buffer: ByteArray, offset: Int, length: Int): Unit {
        var position = offset
        val end = offset + length
        while (position < end) {
            val count = input.read(buffer, position, end - position)
            if (count < 0) throw EOFException()
            if (count == 0) continue
            position += count
        }
    }

    public fun skipBytes(count: Int): Int {
        var skipped = 0
        while (skipped < count) {
            if (input.read() < 0) break
            skipped += 1
        }
        return skipped
    }
}
