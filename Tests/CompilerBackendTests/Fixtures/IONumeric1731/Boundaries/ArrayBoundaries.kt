@file:OptIn(kotlinx.io.InternalIoApi::class)

package kuu1731arrays

import kotlinx.io.*

private class ArrayBoundaryChunks(private val bytes: ByteArray) : RawSource {
    private var position = 0
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (position == bytes.size) return -1L
        val count = minOf(2, bytes.size - position, byteCount.toInt())
        sink.write(bytes, position, position + count)
        position += count
        return count.toLong()
    }
    override fun close() {}
}

private fun readCase(mode: Int, operation: Int, empty: Boolean) {
    val bytes = if (empty) ByteArray(0) else byteArrayOf(1, 2, 3, 4, 5)
    val buffer = Buffer()
    buffer.write(bytes)
    val source: Source = if (mode == 2) ArrayBoundaryChunks(bytes).buffered() else buffer
    val out = ByteArray(7) { 9 }
    print("read:$mode:$operation:$empty:")
    try {
        if (mode == 0) {
            when (operation) {
                0 -> buffer.readTo(out)
                1 -> buffer.readTo(out, 2)
                2 -> buffer.readTo(out, endIndex = 3)
                3 -> buffer.readTo(out, 1, 4)
                4 -> println("count=${buffer.readAtMostTo(out)}")
                5 -> println("count=${buffer.readAtMostTo(out, 2)}")
                6 -> println("count=${buffer.readAtMostTo(out, endIndex = 3)}")
                7 -> println("count=${buffer.readAtMostTo(out, 1, 4)}")
                8 -> println("array=${buffer.readByteArray().joinToString(",")}")
                9 -> println("array=${buffer.readByteArray(0).joinToString(",")}")
                10 -> println("array=${buffer.readByteArray(5).joinToString(",")}")
                11 -> println("array=${buffer.readByteArray(6).joinToString(",")}")
                12 -> buffer.readByteArray(-1)
                13 -> buffer.readTo(out, -1, 3)
                14 -> buffer.readTo(out, 0, 8)
                15 -> buffer.readTo(out, 4, 3)
                16 -> buffer.readAtMostTo(out, -1, 3)
                17 -> buffer.readAtMostTo(out, 0, 8)
                18 -> buffer.readAtMostTo(out, 4, 3)
                19 -> buffer.readTo(out, 7, 7)
                20 -> println("count=${buffer.readAtMostTo(out, 7, 7)}")
                21 -> buffer.readTo(ByteArray(0))
                22 -> println("count=${buffer.readAtMostTo(ByteArray(0))}")
            }
        } else {
            when (operation) {
                0 -> source.readTo(out)
                1 -> source.readTo(out, 2)
                2 -> source.readTo(out, endIndex = 3)
                3 -> source.readTo(out, 1, 4)
                4 -> println("count=${source.readAtMostTo(out)}")
                5 -> println("count=${source.readAtMostTo(out, 2)}")
                6 -> println("count=${source.readAtMostTo(out, endIndex = 3)}")
                7 -> println("count=${source.readAtMostTo(out, 1, 4)}")
                8 -> println("array=${source.readByteArray().joinToString(",")}")
                9 -> println("array=${source.readByteArray(0).joinToString(",")}")
                10 -> println("array=${source.readByteArray(5).joinToString(",")}")
                11 -> println("array=${source.readByteArray(6).joinToString(",")}")
                12 -> source.readByteArray(-1)
                13 -> source.readTo(out, -1, 3)
                14 -> source.readTo(out, 0, 8)
                15 -> source.readTo(out, 4, 3)
                16 -> source.readAtMostTo(out, -1, 3)
                17 -> source.readAtMostTo(out, 0, 8)
                18 -> source.readAtMostTo(out, 4, 3)
                19 -> source.readTo(out, 7, 7)
                20 -> println("count=${source.readAtMostTo(out, 7, 7)}")
                21 -> source.readTo(ByteArray(0))
                22 -> println("count=${source.readAtMostTo(ByteArray(0))}")
            }
        }
        println("ok")
    } catch (e: EOFException) {
        println("EOFException:${e.message}")
    } catch (e: IndexOutOfBoundsException) {
        println("IndexOutOfBoundsException:${e.message}")
    } catch (e: IllegalArgumentException) {
        println("IllegalArgumentException:${e.message}")
    }
    println("out=${out.joinToString(",")};buffer=${source.buffer.size};remaining=${source.readByteArray().joinToString(",")}")
}

private fun writeCase(mode: Int, operation: Int, empty: Boolean) {
    val bytes = if (empty) ByteArray(0) else byteArrayOf(1, 2, 3, 4, 5)
    val buffer = Buffer()
    val sink: Sink = buffer
    print("write:$mode:$operation:$empty:")
    try {
        if (mode == 0) {
            when (operation) {
                0 -> buffer.write(bytes)
                1 -> buffer.write(bytes, 0)
                2 -> buffer.write(bytes, endIndex = bytes.size)
                3 -> buffer.write(bytes, 0, bytes.size)
                4 -> buffer.write(bytes, bytes.size, bytes.size)
                5 -> buffer.write(bytes, -1, bytes.size)
                6 -> buffer.write(bytes, 0, bytes.size + 1)
                7 -> buffer.write(bytes, 1, 0)
                8 -> buffer.write(bytes, -1)
                9 -> buffer.write(bytes, bytes.size + 1)
                10 -> buffer.write(bytes, endIndex = -1)
            }
        } else {
            when (operation) {
                0 -> sink.write(bytes)
                1 -> sink.write(bytes, 0)
                2 -> sink.write(bytes, endIndex = bytes.size)
                3 -> sink.write(bytes, 0, bytes.size)
                4 -> sink.write(bytes, bytes.size, bytes.size)
                5 -> sink.write(bytes, -1, bytes.size)
                6 -> sink.write(bytes, 0, bytes.size + 1)
                7 -> sink.write(bytes, 1, 0)
                8 -> sink.write(bytes, -1)
                9 -> sink.write(bytes, bytes.size + 1)
                10 -> sink.write(bytes, endIndex = -1)
            }
        }
        println("ok")
    } catch (e: IndexOutOfBoundsException) {
        println("IndexOutOfBoundsException:${e.message}")
    } catch (e: IllegalArgumentException) {
        println("IllegalArgumentException:${e.message}")
    }
    println("size=${buffer.size};bytes=${buffer.readByteArray().joinToString(",")}")
}

fun main() {
    for (mode in 0..2) {
        for (empty in listOf(false, true)) {
            for (operation in 0..22) readCase(mode, operation, empty)
        }
    }
    for (mode in 0..1) {
        for (empty in listOf(false, true)) {
            for (operation in 0..10) writeCase(mode, operation, empty)
        }
    }
}
