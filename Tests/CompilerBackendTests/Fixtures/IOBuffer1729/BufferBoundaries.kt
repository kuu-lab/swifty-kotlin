@file:OptIn(kotlinx.io.UnsafeIoApi::class)

package kuu1729producer

import kotlinx.io.*
import kotlinx.io.bytestring.*
import kotlinx.io.unsafe.*

private fun payload(count: Int): ByteArray {
    val bytes = ByteArray(count)
    for (index in bytes.indices) bytes[index] = ((index * 37 + 11) % 251).toByte()
    return bytes
}

private fun digest(bytes: ByteArray): Long {
    var result = 0L
    for (byte in bytes) result = (result * 257L + byte.toLong() + 256L) % 1000000007L
    return result
}

private fun observeFailure(block: () -> Unit): String {
    return try {
        block()
        "NONE"
    } catch (failure: Throwable) {
        when (failure) {
            is EOFException -> "EOF"
            is IndexOutOfBoundsException -> "BOUNDS"
            is IllegalArgumentException -> "ARGUMENT"
            else -> "OTHER"
        }
    }
}

private class DeliberateFailure : RuntimeException("buffer-owned-root")

private class RecordingSink(private val failure: Throwable? = null) : RawSink {
    val data = Buffer()
    override fun write(source: Buffer, byteCount: Long) {
        if (failure != null) {
            val first = minOf(byteCount, 2L)
            data.write(source, first)
            throw failure
        }
        data.write(source, byteCount)
    }
    override fun flush() {}
    override fun close() {}
}

public fun runBufferBoundaries() {
    for (length in intArrayOf(0, 1, 8191, 8192, 8193, 16385)) {
        val bytes = payload(length)
        val buffer = Buffer()
        buffer.write(bytes)
        val copy = buffer.copy()
        val copied = Buffer()
        buffer.copyTo(out = copied)
        val snapshot = buffer.snapshot()
        println("initial:$length:${buffer.size}:${digest(snapshot.toByteArray())}:${digest(copy.snapshot().toByteArray())}:${digest(copied.snapshot().toByteArray())}")
        if (length > 0) {
            for (position in longArrayOf(0L, (length / 2).toLong(), (length - 1).toLong())) {
                println("get:$length:$position:${buffer[position]}:${buffer.get(position)}")
            }
        }
        buffer.skip((length / 2).toLong())
        buffer.writeByte(99)
        println("shared:$length:${buffer.size}:${copy.size}:${digest(snapshot.toByteArray())}:${digest(copy.readByteArray())}:${digest(copied.readByteArray())}:${digest(buffer.readByteArray())}")
        println("drained:$length:${buffer.size}:${copy.size}:${copied.size}")
    }

    val headTail = Buffer()
    headTail.write(payload(8193))
    headTail.skip(8191L)
    headTail.write(payload(8192))
    println("head-tail:${headTail.size}:${headTail[0L]}:${headTail[1L]}:${headTail[2L]}:${headTail[8193L]}:${digest(headTail.readByteArray())}")
    headTail.writeByte(42)
    println("refill:${headTail.size}:${headTail.readByte()}:${headTail.size}")

    val self = Buffer()
    self.write(byteArrayOf(1, 2, 3))
    self.copyTo(out = self, startIndex = 1L, endIndex = 3L)
    println("self-copy:${self.size}:${self.readByteArray().contentToString()}")
    val invalidSelf = Buffer()
    invalidSelf.write(byteArrayOf(1, 2, 3))
    println("self-write:${observeFailure { invalidSelf.write(invalidSelf, 1L) }}:${invalidSelf.size}")
    val original = Buffer()
    original.write(payload(8193))
    val moved = Buffer()
    moved.writeByte(7)
    val retained = original.copy()
    moved.write(original, 8192L)
    original.writeByte(8)
    moved.writeByte(9)
    println("move:${original.size}:${moved.size}:${retained.size}:${digest(original.readByteArray())}:${digest(moved.readByteArray())}:${digest(retained.readByteArray())}")

    val partial = Buffer()
    partial.write(byteArrayOf(1, 2, 3))
    val destination = ByteArray(5) { 77 }
    println("partial:${partial.readAtMostTo(destination, startIndex = 1, endIndex = 5)}:${partial.size}:${destination.contentToString()}")
    println("eof:${partial.readAtMostTo(destination, startIndex = 1, endIndex = 5)}:${destination.contentToString()}")
    val empty = Buffer()
    println("zero-empty:${empty.readAtMostTo(ByteArray(0))}:${empty.readAtMostTo(Buffer(), 0L)}")
    val nonEmpty = Buffer()
    nonEmpty.writeByte(5)
    println("zero-nonempty:${nonEmpty.readAtMostTo(ByteArray(0))}:${nonEmpty.readAtMostTo(Buffer(), 0L)}:${nonEmpty.size}")
    println("skip-eof:${observeFailure { nonEmpty.skip(2L) }}:${nonEmpty.size}")
    val toSink = Buffer()
    toSink.write(byteArrayOf(4, 5, 6))
    val sink = RecordingSink()
    println("write-eof:${observeFailure { toSink.readTo(sink, 5L) }}:${toSink.size}:${sink.data.readByteArray().contentToString()}")
    val failingSource = Buffer()
    failingSource.write(byteArrayOf(1, 2, 3, 4, 5))
    val root = DeliberateFailure()
    val failingSink = RecordingSink(root)
    var sameRoot = false
    try { failingSource.readTo(failingSink, 5L) } catch (caught: Throwable) { sameRoot = caught === root }
    println("throw-root:$sameRoot:${failingSource.size}:${failingSink.data.readByteArray().contentToString()}:${failingSource.readByteArray().contentToString()}")

    val indexed = Buffer()
    indexed.write(byteArrayOf(10, 11, 12))
    for (position in longArrayOf(-1L, Long.MIN_VALUE, 3L, Long.MAX_VALUE)) {
        println("get-invalid:$position:${observeFailure { indexed[position] }}:${observeFailure { indexed.get(position) }}:${indexed.size}")
    }
    println("copy-invalid:${observeFailure { indexed.copyTo(Buffer(), startIndex = -1L) }}:${observeFailure { indexed.copyTo(Buffer(), startIndex = 2L, endIndex = 1L) }}:${observeFailure { indexed.copyTo(Buffer(), endIndex = Long.MAX_VALUE) }}:${indexed.size}")
    println("skip-invalid:${observeFailure { indexed.skip(-1L) }}:${indexed.size}")
    val search = Buffer()
    search.write(ByteArray(8191) { 1 })
    search.write(byteArrayOf(2, 3, 4))
    println("search:${search.indexOf(byte = 2)}:${search.indexOf(byte = 2, startIndex = 8192L)}:${search.indexOf(byteString = ByteString(1, 2, 3))}:${search.indexOf(byteString = ByteString())}:${search.size}")

    var firstRead: SegmentReadContext? = null
    var firstWrite: SegmentWriteContext? = null
    var firstIteration: BufferIterationContext? = null
    for (round in 0..1) {
        val unsafe = Buffer()
        UnsafeBufferOperations.writeToTail(unsafe, minimumCapacity = 1) { context, segment ->
            if (firstWrite == null) firstWrite = context
            println("write-context:$round:${firstWrite === context}")
            context.setUnchecked(segment, 0, 55)
            1
        }
        UnsafeBufferOperations.readFromHead(unsafe) { context, segment ->
            if (firstRead == null) firstRead = context
            println("read-context:$round:${firstRead === context}:${context.getUnchecked(segment, 0)}")
            0
        }
        UnsafeBufferOperations.iterate(unsafe) { context, segment ->
            if (firstIteration == null) firstIteration = context
            println("iteration-context:$round:${firstIteration === context}:${segment != null}:${if (segment == null) false else context.next(segment) == null}")
        }
        println("unsafe-state:$round:${unsafe.size}:${unsafe.readByte()}:${unsafe.size}")
    }
    println("done")
}
