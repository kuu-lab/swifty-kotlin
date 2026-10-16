@file:OptIn(kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class)

import java.nio.ByteBuffer
import kotlinx.io.bytestring.getByteString

fun readRemainingByteBufferAsByteString() {
    val buffer = ByteBuffer.wrap(byteArrayOf(9, 1, 2, 3, 8)).position(1).limit(4)
    val bytes = buffer.getByteString()
    println("remaining:${bytes.size}:${bytes[0]}:${bytes[1]}:${bytes[2]}:${buffer.position()}:${buffer.remaining()}")

    val emptyBuffer = ByteBuffer.allocate(2).position(2)
    val emptyBytes = emptyBuffer.getByteString()
    println("empty:${emptyBytes.size}:${emptyBuffer.position()}")
}
