@file:OptIn(kotlinx.io.InternalIoApi::class)

package kuu1731boundaries

import kotlinx.io.*

private class ThreeByteSource(private val bytes: ByteArray) : RawSource {
    private var position = 0
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (position == bytes.size) return -1L
        val count = minOf(3, bytes.size - position, byteCount.toInt())
        sink.write(bytes, position, position + count)
        position += count
        return count.toLong()
    }
    override fun close() {}
}

// Modes cover Buffer-typed and Source/Sink-typed dispatch, one-byte segment
// remainder, and small buffered upstream reads. Values and post-read sizes are
// observed independently of the implementation under test.
private fun sourceFor(buffer: Buffer, mode: Int): Source {
    if (mode == 2) {
        val bytes = buffer.readByteArray()
        buffer.write(ByteArray(8191))
        buffer.write(bytes)
        buffer.skip(8191L)
    }
    return if (mode == 3) ThreeByteSource(buffer.readByteArray()).buffered() else buffer
}

private fun integers(mode: Int, little: Boolean) {
    for (value in listOf(Byte.MIN_VALUE, (-1).toByte(), 0.toByte(), Byte.MAX_VALUE)) {
        val buffer = Buffer()
        val sink: Sink = buffer
        if (mode == 0) buffer.writeByte(value) else sink.writeByte(value)
        val source = sourceFor(buffer, mode)
        val actual = if (mode == 0) buffer.readByte() else source.readByte()
        println("byte:$mode:$little:$value:$actual:${source.buffer.size}")
    }
    for (value in listOf(Short.MIN_VALUE, (-1).toShort(), 0.toShort(), Short.MAX_VALUE, 0x1234.toShort())) {
        val buffer = Buffer()
        val sink: Sink = buffer
        if (mode == 0) {
            if (little) buffer.writeShortLe(value) else buffer.writeShort(value)
        } else {
            if (little) sink.writeShortLe(value) else sink.writeShort(value)
        }
        val source = sourceFor(buffer, mode)
        val actual = if (mode == 0) {
            if (little) buffer.readShortLe() else buffer.readShort()
        } else {
            if (little) source.readShortLe() else source.readShort()
        }
        println("short:$mode:$little:$value:$actual:${source.buffer.size}")
    }
    for (value in listOf(Int.MIN_VALUE, -1, 0, Int.MAX_VALUE, 0x12345678)) {
        val buffer = Buffer()
        val sink: Sink = buffer
        if (mode == 0) {
            if (little) buffer.writeIntLe(value) else buffer.writeInt(value)
        } else {
            if (little) sink.writeIntLe(value) else sink.writeInt(value)
        }
        val source = sourceFor(buffer, mode)
        val actual = if (mode == 0) {
            if (little) buffer.readIntLe() else buffer.readInt()
        } else {
            if (little) source.readIntLe() else source.readInt()
        }
        println("int:$mode:$little:$value:$actual:${source.buffer.size}")
    }
    for (value in listOf(Long.MIN_VALUE, -1L, 0L, Long.MAX_VALUE, 0x123456789abcdefL)) {
        val buffer = Buffer()
        val sink: Sink = buffer
        if (mode == 0) {
            if (little) buffer.writeLongLe(value) else buffer.writeLong(value)
        } else {
            if (little) sink.writeLongLe(value) else sink.writeLong(value)
        }
        val source = sourceFor(buffer, mode)
        val actual = if (mode == 0) {
            if (little) buffer.readLongLe() else buffer.readLong()
        } else {
            if (little) source.readLongLe() else source.readLong()
        }
        println("long:$mode:$little:$value:$actual:${source.buffer.size}")
    }
}

private fun unsigned(mode: Int, little: Boolean) {
    for (value in listOf(0uL, ULong.MAX_VALUE)) {
        val buffer = Buffer()
        val sink: Sink = buffer
        if (mode == 0) {
            buffer.writeUByte(value.toUByte())
            if (little) {
                buffer.writeUShortLe(value.toUShort())
                buffer.writeUIntLe(value.toUInt())
                buffer.writeULongLe(value)
            } else {
                buffer.writeUShort(value.toUShort())
                buffer.writeUInt(value.toUInt())
                buffer.writeULong(value)
            }
        } else {
            sink.writeUByte(value.toUByte())
            if (little) {
                sink.writeUShortLe(value.toUShort())
                sink.writeUIntLe(value.toUInt())
                sink.writeULongLe(value)
            } else {
                sink.writeUShort(value.toUShort())
                sink.writeUInt(value.toUInt())
                sink.writeULong(value)
            }
        }
        val source = sourceFor(buffer, mode)
        if (mode == 0) {
            println("unsigned-byte:$mode:$little:${buffer.readUByte()}")
            println("unsigned-short:$mode:$little:${if (little) buffer.readUShortLe() else buffer.readUShort()}")
            println("unsigned-int:$mode:$little:${if (little) buffer.readUIntLe() else buffer.readUInt()}")
            println("unsigned-long:$mode:$little:${if (little) buffer.readULongLe() else buffer.readULong()}")
        } else {
            println("unsigned-byte:$mode:$little:${source.readUByte()}")
            println("unsigned-short:$mode:$little:${if (little) source.readUShortLe() else source.readUShort()}")
            println("unsigned-int:$mode:$little:${if (little) source.readUIntLe() else source.readUInt()}")
            println("unsigned-long:$mode:$little:${if (little) source.readULongLe() else source.readULong()}")
        }
        println("unsigned-size:$mode:$little:${source.buffer.size}")
    }
}

private fun floating(mode: Int, little: Boolean) {
    for (bits in listOf(0, Int.MIN_VALUE, 1, -2147483647, 0x7f7fffff, -8388609,
        0x7f800000, -8388608, 0x7fc01234, -4189644)) {
        val buffer = Buffer()
        val sink: Sink = buffer
        val value = Float.fromBits(bits)
        if (mode == 0) {
            if (little) buffer.writeFloatLe(value) else buffer.writeFloat(value)
        } else {
            if (little) sink.writeFloatLe(value) else sink.writeFloat(value)
        }
        val wire = buffer.copy().readByteArray().joinToString(",")
        val source = sourceFor(buffer, mode)
        val result = if (mode == 0) {
            if (little) buffer.readFloatLe() else buffer.readFloat()
        } else {
            if (little) source.readFloatLe() else source.readFloat()
        }
        println("float:$mode:$little:$bits:$wire:${result.toRawBits()}:${result.isNaN()}:${source.buffer.size}")
        val raw = Buffer()
        if (little) raw.writeIntLe(bits) else raw.writeInt(bits)
        val rawSource: Source = sourceFor(raw, mode)
        val rawResult = if (little) rawSource.readFloatLe() else rawSource.readFloat()
        println("float-raw:$mode:$little:$bits:${rawResult.toRawBits()}")
    }
    for (bits in listOf(0L, Long.MIN_VALUE, 1L, -9223372036854775807L,
        0x7fefffffffffffffL, -4503599627370497L, 0x7ff0000000000000L,
        -4503599627370496L, 0x7ff8000000001234L, -2251799813680588L)) {
        val buffer = Buffer()
        val sink: Sink = buffer
        val value = Double.fromBits(bits)
        if (mode == 0) {
            if (little) buffer.writeDoubleLe(value) else buffer.writeDouble(value)
        } else {
            if (little) sink.writeDoubleLe(value) else sink.writeDouble(value)
        }
        val wire = buffer.copy().readByteArray().joinToString(",")
        val source = sourceFor(buffer, mode)
        val result = if (mode == 0) {
            if (little) buffer.readDoubleLe() else buffer.readDouble()
        } else {
            if (little) source.readDoubleLe() else source.readDouble()
        }
        println("double:$mode:$little:$bits:$wire:${result.toRawBits()}:${result.isNaN()}:${source.buffer.size}")
        val raw = Buffer()
        if (little) raw.writeLongLe(bits) else raw.writeLong(bits)
        val rawSource: Source = sourceFor(raw, mode)
        val rawResult = if (little) rawSource.readDoubleLe() else rawSource.readDouble()
        println("double-raw:$mode:$little:$bits:${rawResult.toRawBits()}")
    }
}

fun main() {
    for (mode in 0..3) {
        for (little in listOf(false, true)) {
            integers(mode, little)
            unsigned(mode, little)
            floating(mode, little)
        }
    }
}
