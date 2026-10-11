@file:OptIn(kotlinx.io.InternalIoApi::class)

package kuu1731eof

import kotlinx.io.*

private class EofChunks(private val bytes: ByteArray) : RawSource {
    private var position = 0
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (position == bytes.size) return -1L
        val count = minOf(1, byteCount.toInt())
        sink.write(bytes, position, position + count)
        position += count
        return count.toLong()
    }
    override fun close() {}
}

private fun runCase(mode: Int, operation: Int, available: Int) {
    val bytes = ByteArray(available) { (it + 1).toByte() }
    val buffer = Buffer()
    buffer.write(bytes)
    val source: Source = if (mode == 2) EofChunks(bytes).buffered() else buffer
    print("eof:$mode:$operation:$available:")
    try {
        if (mode == 0) {
            when (operation) {
                0 -> buffer.readByte()
                1 -> buffer.readUByte()
                2 -> buffer.readShort()
                3 -> buffer.readShortLe()
                4 -> buffer.readUShort()
                5 -> buffer.readUShortLe()
                6 -> buffer.readInt()
                7 -> buffer.readIntLe()
                8 -> buffer.readUInt()
                9 -> buffer.readUIntLe()
                10 -> buffer.readFloat()
                11 -> buffer.readFloatLe()
                12 -> buffer.readLong()
                13 -> buffer.readLongLe()
                14 -> buffer.readULong()
                15 -> buffer.readULongLe()
                16 -> buffer.readDouble()
                17 -> buffer.readDoubleLe()
            }
        } else {
            when (operation) {
                0 -> source.readByte()
                1 -> source.readUByte()
                2 -> source.readShort()
                3 -> source.readShortLe()
                4 -> source.readUShort()
                5 -> source.readUShortLe()
                6 -> source.readInt()
                7 -> source.readIntLe()
                8 -> source.readUInt()
                9 -> source.readUIntLe()
                10 -> source.readFloat()
                11 -> source.readFloatLe()
                12 -> source.readLong()
                13 -> source.readLongLe()
                14 -> source.readULong()
                15 -> source.readULongLe()
                16 -> source.readDouble()
                17 -> source.readDoubleLe()
            }
        }
        println("unexpected-success")
    } catch (e: EOFException) {
        println("EOFException:${e.message}")
    }
    println("size=${source.buffer.size};remaining=${source.readByteArray().joinToString(",")}")
}

fun main() {
    for (mode in 0..2) {
        for (operation in 0..17) {
            val width = if (operation < 2) 1 else if (operation < 6) 2 else if (operation < 12) 4 else 8
            for (available in 0 until width) runCase(mode, operation, available)
        }
    }
}
