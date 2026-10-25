@file:OptIn(kotlin.ExperimentalUnsignedTypes::class)

package java.io

public open class DataOutputStream(private val output: OutputStream) : OutputStream {
    public override fun write(value: Int): Unit = output.write(value)

    public override fun write(buffer: ByteArray): Unit = output.write(buffer)

    public override fun write(buffer: ByteArray, offset: Int, length: Int): Unit = output.write(buffer, offset, length)

    public override fun flush(): Unit = output.flush()

    public override fun close(): Unit = output.close()

    public fun writeBoolean(value: Boolean): Unit = write(if (value) 1 else 0)

    public fun writeByte(value: Int): Unit = write(value)

    public fun writeShort(value: Int): Unit {
        write(value ushr 8)
        write(value)
    }

    public fun writeChar(value: Int): Unit = writeShort(value)

    public fun writeChar(value: Char): Unit = writeShort(value.code)

    public fun writeInt(value: Int): Unit {
        write(value ushr 24)
        write(value ushr 16)
        write(value ushr 8)
        write(value)
    }

    public fun writeLong(value: Long): Unit {
        writeInt((value ushr 32).toInt())
        writeInt(value.toInt())
    }

    public fun writeFloat(value: Float): Unit = writeInt(value.toBits())

    public fun writeDouble(value: Double): Unit = writeLong(value.toBits())

    public fun writeBytes(value: String): Unit {
        for (character in value) write(character.code)
    }

    public fun writeChars(value: String): Unit {
        for (character in value) writeChar(character)
    }

    public fun writeUTF(value: String): Unit {
        var byteCount = 0
        for (character in value) {
            val code = character.code
            byteCount += when {
                code in 1..0x7f -> 1
                code <= 0x7ff -> 2
                else -> 3
            }
        }
        writeShort(byteCount)
        for (character in value) {
            val code = character.code
            when {
                code in 1..0x7f -> writeByte(code)
                code <= 0x7ff -> {
                    writeByte(0xc0 or ((code shr 6) and 0x1f))
                    writeByte(0x80 or (code and 0x3f))
                }
                else -> {
                    writeByte(0xe0 or ((code shr 12) and 0x0f))
                    writeByte(0x80 or ((code shr 6) and 0x3f))
                    writeByte(0x80 or (code and 0x3f))
                }
            }
        }
    }
}
