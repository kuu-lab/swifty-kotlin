@file:OptIn(UnsafeIoApi::class)

import kotlinx.io.*
import kotlinx.io.unsafe.UnsafeBufferOperations

private class BoundaryException : RuntimeException()

private fun Buffer.readByteArray(): ByteArray = ByteArray(size.toInt()) { readByte() }

private fun expect(condition: Boolean) {
    if (!condition) throw IllegalStateException("unsafe boundary assertion failed")
}

private inline fun <reified T : Throwable> expectFailure(block: () -> Unit) {
    var failure: Throwable? = null
    try {
        block()
    } catch (caught: Throwable) {
        failure = caught
    }
    expect(failure is T)
}

private fun assertRawReadCommitRejected(commit: Int) {
    val buffer = Buffer().apply { writeInt(42) }
    expectFailure<IllegalStateException> {
        UnsafeBufferOperations.readFromHead(buffer) { _, _, _ -> commit }
    }
    expect(buffer.size == 4L)
    expect(buffer.readInt() == 42)
}

private fun assertContextReadCommitRejected(commit: Int) {
    val buffer = Buffer().apply { writeInt(42) }
    expectFailure<IllegalStateException> {
        UnsafeBufferOperations.readFromHead(buffer) { _, _ -> commit }
    }
    expect(buffer.size == 4L)
    expect(buffer.readInt() == 42)
}

private fun assertRawWriteCommitRejected(commit: Int) {
    val buffer = Buffer()
    expectFailure<IllegalStateException> {
        UnsafeBufferOperations.writeToTail(buffer, 1) { _, _, _ -> commit }
    }
    expect(buffer.exhausted())
}

private fun assertContextWriteCommitRejected(commitTooLarge: Boolean) {
    val buffer = Buffer()
    expectFailure<IllegalStateException> {
        UnsafeBufferOperations.writeToTail(buffer, 1) { _, segment ->
            if (commitTooLarge) segment.remainingCapacity + 1 else -1
        }
    }
    expect(buffer.exhausted())
}

private fun writeCapacityAndZeroCommit() {
    val maximum = UnsafeBufferOperations.maxSafeWriteCapacity

    val byteBuffer = Buffer()
    val byteWrite = UnsafeBufferOperations.writeToTail(byteBuffer, maximum) { data, start, end ->
        expect(end - start == maximum)
        data[start] = 0x11
        data[end - 1] = 0x22
        end - start
    }
    expect(byteWrite == maximum)
    expect(byteBuffer.size == maximum.toLong())

    val contextBuffer = Buffer()
    val contextWrite = UnsafeBufferOperations.writeToTail(contextBuffer, maximum) { ctx, segment ->
        expect(segment.remainingCapacity == maximum)
        ctx.setUnchecked(segment, 0, 0x11)
        ctx.setUnchecked(segment, maximum - 1, 0x22)
        maximum
    }
    expect(contextWrite == maximum)
    expect(contextBuffer.size == maximum.toLong())

    var callbacks = 0
    for (minimumCapacity in listOf(0, -1, maximum + 1)) {
        val invalidByteBuffer = Buffer()
        expectFailure<IllegalArgumentException> {
            UnsafeBufferOperations.writeToTail(invalidByteBuffer, minimumCapacity) { _, _, _ ->
                callbacks++
                0
            }
        }
        expect(invalidByteBuffer.exhausted())

        val invalidContextBuffer = Buffer()
        expectFailure<IllegalArgumentException> {
            UnsafeBufferOperations.writeToTail(invalidContextBuffer, minimumCapacity) { _, _ ->
                callbacks++
                0
            }
        }
        expect(invalidContextBuffer.exhausted())
    }
    expect(callbacks == 0)

    val emptyBuffer = Buffer()
    expect(UnsafeBufferOperations.writeToTail(emptyBuffer, 1) { _, _, _ -> 0 } == 0)
    expect(emptyBuffer.exhausted())
    expect(UnsafeBufferOperations.writeToTail(emptyBuffer, 1) { _, _ -> 0 } == 0)
    expect(emptyBuffer.exhausted())

    val nonEmptyBuffer = Buffer().apply { writeInt(42) }
    expect(UnsafeBufferOperations.writeToTail(nonEmptyBuffer, 1) { _, _, _ -> 0 } == 0)
    expect(UnsafeBufferOperations.writeToTail(nonEmptyBuffer, 1) { _, _ -> 0 } == 0)
    expect(nonEmptyBuffer.size == 4L)
    expect(nonEmptyBuffer.readInt() == 42)
}

private fun readCommitBoundaries() {
    assertRawReadCommitRejected(-1)
    assertRawReadCommitRejected(5)
    assertContextReadCommitRejected(-1)
    assertContextReadCommitRejected(5)

    val byteBuffer = Buffer().apply { writeString("read") }
    expect(UnsafeBufferOperations.readFromHead(byteBuffer) { _, _, _ -> 0 } == 0)
    expect(byteBuffer.size == 4L)

    val contextBuffer = Buffer().apply { writeString("read") }
    expect(UnsafeBufferOperations.readFromHead(contextBuffer) { _, _ -> 0 } == 0)
    expect(contextBuffer.size == 4L)
    expect(byteBuffer.readByteArray().decodeToString() == "read")
    expect(contextBuffer.readByteArray().decodeToString() == "read")
}

private fun writeCommitBoundaries() {
    assertRawWriteCommitRejected(-1)
    assertRawWriteCommitRejected(UnsafeBufferOperations.maxSafeWriteCapacity + 1)
    assertContextWriteCommitRejected(commitTooLarge = false)
    assertContextWriteCommitRejected(commitTooLarge = true)
}

private fun callbackExceptionState() {
    val byteWriteBuffer = Buffer().apply { writeString("seed") }
    expectFailure<BoundaryException> {
        UnsafeBufferOperations.writeToTail(byteWriteBuffer, 1) { data, start, _ ->
            data[start] = '!'.code.toByte()
            throw BoundaryException()
        }
    }
    expect(byteWriteBuffer.size == 4L)
    byteWriteBuffer.writeString("!")
    expect(byteWriteBuffer.readByteArray().decodeToString() == "seed!")

    val contextWriteBuffer = Buffer().apply { writeString("seed") }
    expectFailure<BoundaryException> {
        UnsafeBufferOperations.writeToTail(contextWriteBuffer, 1) { ctx, segment ->
            ctx.setUnchecked(segment, 0, '!'.code.toByte())
            throw BoundaryException()
        }
    }
    expect(contextWriteBuffer.size == 4L)
    contextWriteBuffer.writeString("!")
    expect(contextWriteBuffer.readByteArray().decodeToString() == "seed!")

    val readBuffer = Buffer().apply { writeString("seed") }
    expectFailure<BoundaryException> {
        UnsafeBufferOperations.readFromHead(readBuffer) { _, _, _ -> throw BoundaryException() }
    }
    expect(readBuffer.size == 4L)
    expectFailure<BoundaryException> {
        UnsafeBufferOperations.readFromHead(readBuffer) { _, _ -> throw BoundaryException() }
    }
    expect(readBuffer.size == 4L)
    expect(readBuffer.readByteArray().decodeToString() == "seed")
}

fun main() {
    writeCapacityAndZeroCommit()
    println("capacityAndZeroCommit:pass")
    readCommitBoundaries()
    println("readCommitBoundaries:pass")
    writeCommitBoundaries()
    println("writeCommitBoundaries:pass")
    callbackExceptionState()
    println("callbackExceptionState:pass")
}
