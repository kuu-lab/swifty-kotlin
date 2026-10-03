/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 * Copyright (C) 2018 Square, Inc. Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-io core/common/src/Buffer.kt and Segment.kt (tag 0.9.1).
 * Segments form a doubly-linked ring. Copies share byte storage, while whole-segment
 * transfers move ownership. Pooling and the public unsafe segment API are not exposed here.
 */
package kotlinx.io

internal const val SEGMENT_SIZE_HINT: Int = 8192

internal class BufferSegment(
    val data: ByteArray = ByteArray(SEGMENT_SIZE_HINT),
    var pos: Int = 0,
    var limit: Int = 0,
    var shared: Boolean = false,
    val owner: Boolean = true
) {
    var next: BufferSegment? = null
    var prev: BufferSegment? = null

    fun sharedCopy(): BufferSegment {
        shared = true
        return BufferSegment(data, pos, limit, true, false)
    }

    fun writeTo(sink: BufferSegment, byteCount: Int) {
        if (sink.limit + byteCount > SEGMENT_SIZE_HINT) {
            var i = 0
            val count = sink.limit - sink.pos
            while (i < count) {
                sink.data[i] = sink.data[sink.pos + i]
                i += 1
            }
            sink.limit = count
            sink.pos = 0
        }
        var i = 0
        while (i < byteCount) {
            sink.data[sink.limit + i] = data[pos + i]
            i += 1
        }
        sink.limit += byteCount
        pos += byteCount
    }
}

/**
 * An in-memory byte queue implementing both [Source] and [Sink].
 *
 * Data is stored in fixed-size segments, so the total size is not limited by a single
 * array's capacity. [close], [flush], [emit] and [hintEmit] do not affect its state.
 */
public class Buffer : Source, Sink {
    internal var head: BufferSegment? = null
    private var sizeMut: Long = 0L

    public val size: Long
        get() = sizeMut

    override val buffer: Buffer
        get() = this

    private fun pushSegment(segment: BufferSegment) {
        val first = head
        if (first == null) {
            segment.next = segment
            segment.prev = segment
            head = segment
        } else {
            val tail = first.prev!!
            tail.next = segment
            segment.prev = tail
            segment.next = first
            first.prev = segment
        }
    }

    private fun popHead(): BufferSegment {
        val segment = head!!
        val next = segment.next!!
        if (next === segment) {
            head = null
        } else {
            val tail = segment.prev!!
            tail.next = next
            next.prev = tail
            head = next
        }
        segment.next = null
        segment.prev = null
        return segment
    }

    private fun writableSegment(minimumCapacity: Int): BufferSegment {
        val first = head
        if (first != null) {
            val tail = first.prev!!
            if (tail.owner && tail.limit + minimumCapacity <= SEGMENT_SIZE_HINT) {
                return tail
            }
        }
        val segment = BufferSegment()
        pushSegment(segment)
        return segment
    }

    internal fun completeSegmentByteCount(): Long {
        val first = head ?: return 0L
        val tail = first.prev!!
        if (tail.owner && tail.limit < SEGMENT_SIZE_HINT) {
            return size - (tail.limit - tail.pos).toLong()
        }
        return size
    }

    override fun exhausted(): Boolean = size == 0L

    override fun require(byteCount: Long) {
        if (byteCount < 0L) {
            throw IllegalArgumentException("byteCount: $byteCount")
        }
        if (size < byteCount) {
            throw EOFException("Buffer doesn't contain required number of bytes (size: $size, required: $byteCount)")
        }
    }

    override fun request(byteCount: Long): Boolean {
        if (byteCount < 0L) {
            throw IllegalArgumentException("byteCount: $byteCount < 0")
        }
        return size >= byteCount
    }

    override fun readByte(): Byte {
        require(1L)
        val segment = head!!
        val value = segment.data[segment.pos]
        segment.pos += 1
        sizeMut -= 1L
        if (segment.pos == segment.limit) {
            popHead()
        }
        return value
    }

    override fun readShort(): Short {
        require(2L)
        return ((readByte().toInt() and 0xff shl 8) or (readByte().toInt() and 0xff)).toShort()
    }

    override fun readInt(): Int {
        require(4L)
        return (readShort().toInt() shl 16) or (readShort().toInt() and 0xffff)
    }

    override fun readLong(): Long {
        require(8L)
        return (readInt().toLong() shl 32) or (readInt().toLong() and 0xffffffffL)
    }

    override fun skip(byteCount: Long) {
        checkByteCount(byteCount)
        var remaining = byteCount
        while (remaining > 0L) {
            val segment = head ?: throw EOFException("Buffer exhausted before skipping $byteCount bytes.")
            val count = minOf(remaining, segment.limit - segment.pos).toInt()
            segment.pos += count
            sizeMut -= count.toLong()
            remaining -= count.toLong()
            if (segment.pos == segment.limit) {
                popHead()
            }
        }
    }

    public fun clear() {
        skip(size)
    }

    public operator fun get(position: Long): Byte {
        if (position < 0L || position >= size) {
            throw IndexOutOfBoundsException("position ($position) is not within the range [0..size($size))")
        }
        var segment = head!!
        var offset = position
        while (offset >= (segment.limit - segment.pos).toLong()) {
            offset -= (segment.limit - segment.pos).toLong()
            segment = segment.next!!
        }
        return segment.data[segment.pos + offset.toInt()]
    }

    public fun indexOf(byte: Byte, startIndex: Long = 0L, endIndex: Long = size): Long {
        val endOffset = if (endIndex > size) size else endIndex
        checkBounds(size, startIndex, endOffset)
        if (startIndex == endOffset) return -1L
        var segment = head!!
        var segmentOffset = 0L
        while (startIndex >= segmentOffset + (segment.limit - segment.pos).toLong()) {
            segmentOffset += (segment.limit - segment.pos).toLong()
            segment = segment.next!!
        }
        var index = startIndex
        while (index < endOffset) {
            val limit = minOf(endOffset - segmentOffset, segment.limit - segment.pos).toInt()
            var offset = (index - segmentOffset).toInt()
            while (offset < limit) {
                if (segment.data[segment.pos + offset] == byte) return segmentOffset + offset.toLong()
                offset += 1
            }
            segmentOffset += (segment.limit - segment.pos).toLong()
            index = segmentOffset
            segment = segment.next!!
        }
        return -1L
    }

    public fun copyTo(out: Buffer, startIndex: Long = 0L, endIndex: Long = size) {
        checkBounds(size, startIndex, endIndex)
        var remaining = endIndex - startIndex
        if (remaining == 0L) return
        var segment = head!!
        var offset = startIndex
        while (offset >= (segment.limit - segment.pos).toLong()) {
            offset -= (segment.limit - segment.pos).toLong()
            segment = segment.next!!
        }
        while (remaining > 0L) {
            val copy = segment.sharedCopy()
            copy.pos += offset.toInt()
            val count = minOf(remaining, copy.limit - copy.pos).toInt()
            copy.limit = copy.pos + count
            out.pushSegment(copy)
            out.sizeMut += count.toLong()
            remaining -= count.toLong()
            offset = 0L
            segment = segment.next!!
        }
    }

    public fun copy(): Buffer {
        val result = Buffer()
        copyTo(result, 0L, size)
        return result
    }

    override fun readAtMostTo(sink: ByteArray, startIndex: Int, endIndex: Int): Int {
        checkBounds(sink.size, startIndex, endIndex)
        val segment = head ?: return -1
        val available = segment.limit - segment.pos
        val requested = endIndex - startIndex
        val count = if (requested < available) requested else available
        var i = 0
        while (i < count) {
            sink[startIndex + i] = segment.data[segment.pos + i]
            i += 1
        }
        segment.pos += count
        sizeMut -= count.toLong()
        if (segment.pos == segment.limit) {
            popHead()
        }
        return count
    }

    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        checkByteCount(byteCount)
        if (size == 0L) return -1L
        val count = if (byteCount < size) byteCount else size
        sink.write(this, count)
        return count
    }

    override fun readTo(sink: RawSink, byteCount: Long) {
        checkByteCount(byteCount)
        if (size < byteCount) {
            sink.write(this, size)
            throw EOFException("Buffer exhausted before writing $byteCount bytes. Only $size bytes were written.")
        }
        sink.write(this, byteCount)
    }

    override fun transferTo(sink: RawSink): Long {
        val count = size
        if (count > 0L) sink.write(this, count)
        return count
    }

    override fun transferFrom(source: RawSource): Long {
        var total = 0L
        while (true) {
            val read = source.readAtMostTo(this, SEGMENT_SIZE_HINT.toLong())
            if (read == -1L) return total
            total += read
        }
    }

    override fun peek(): Source = PeekSource(this).buffered()

    override fun write(source: ByteArray, startIndex: Int, endIndex: Int) {
        checkBounds(source.size, startIndex, endIndex)
        var offset = startIndex
        while (offset < endIndex) {
            val tail = writableSegment(1)
            val available = SEGMENT_SIZE_HINT - tail.limit
            val remaining = endIndex - offset
            val count = if (remaining < available) remaining else available
            var i = 0
            while (i < count) {
                tail.data[tail.limit + i] = source[offset + i]
                i += 1
            }
            tail.limit += count
            offset += count
        }
        sizeMut += (endIndex - startIndex).toLong()
    }

    override fun write(source: RawSource, byteCount: Long) {
        checkByteCount(byteCount)
        var remaining = byteCount
        while (remaining > 0L) {
            val read = source.readAtMostTo(this, remaining)
            if (read == -1L) {
                throw EOFException("Source exhausted before reading $byteCount bytes. Only ${byteCount - remaining} were read.")
            }
            remaining -= read
        }
    }

    override fun write(source: Buffer, byteCount: Long) {
        if (source === this) throw IllegalArgumentException("source == this")
        checkOffsetAndCount(source.size, 0L, byteCount)
        var remaining = byteCount
        while (remaining > 0L) {
            val segment = source.head!!
            val available = segment.limit - segment.pos
            val first = head
            val tail = first?.prev
            if (remaining < available.toLong()) {
                val count = remaining.toInt()
                if (tail != null && tail.owner &&
                    count <= SEGMENT_SIZE_HINT - tail.limit + (if (tail.shared) 0 else tail.pos)) {
                    segment.writeTo(tail, count)
                } else {
                    val prefix: BufferSegment
                    if (count >= 1024) {
                        prefix = segment.sharedCopy()
                        prefix.limit = prefix.pos + count
                    } else {
                        prefix = BufferSegment()
                        var i = 0
                        while (i < count) {
                            prefix.data[i] = segment.data[segment.pos + i]
                            i += 1
                        }
                        prefix.limit = count
                    }
                    segment.pos += count
                    pushSegment(prefix)
                }
                source.sizeMut -= remaining
                sizeMut += remaining
                return
            }
            val moved = source.popHead()
            if (tail != null && tail.owner &&
                available <= SEGMENT_SIZE_HINT - tail.limit + (if (tail.shared) 0 else tail.pos)) {
                moved.writeTo(tail, available)
            } else {
                pushSegment(moved)
            }
            source.sizeMut -= available.toLong()
            sizeMut += available.toLong()
            remaining -= available.toLong()
        }
    }

    override fun writeByte(byte: Byte) {
        val tail = writableSegment(1)
        tail.data[tail.limit] = byte
        tail.limit += 1
        sizeMut += 1L
    }

    override fun writeShort(short: Short) {
        val tail = writableSegment(2)
        val value = short.toInt()
        tail.data[tail.limit] = (value ushr 8 and 0xff).toByte()
        tail.data[tail.limit + 1] = (value and 0xff).toByte()
        tail.limit += 2
        sizeMut += 2L
    }

    override fun writeInt(int: Int) {
        val tail = writableSegment(4)
        var shift = 24
        var i = 0
        while (i < 4) {
            tail.data[tail.limit + i] = (int ushr shift and 0xff).toByte()
            shift -= 8
            i += 1
        }
        tail.limit += 4
        sizeMut += 4L
    }

    override fun writeLong(long: Long) {
        val tail = writableSegment(8)
        var shift = 56
        var i = 0
        while (i < 8) {
            tail.data[tail.limit + i] = (long ushr shift and 0xffL).toByte()
            shift -= 8
            i += 1
        }
        tail.limit += 8
        sizeMut += 8L
    }

    override fun hintEmit() {}
    override fun emit() {}
    override fun flush() {}
    override fun close() {}

    override fun toString(): String {
        if (size == 0L) return "Buffer(size=0)"
        val length = if (size < 64L) size.toInt() else 64
        val builder = StringBuilder()
        var i = 0
        while (i < length) {
            val byte = get(i.toLong()).toInt() and 0xff
            builder.append(HEX_DIGIT_CHARS[(byte shr 4) and 0xf])
            builder.append(HEX_DIGIT_CHARS[byte and 0xf])
            i += 1
        }
        if (size > 64L) builder.append('…')
        return "Buffer(size=$size hex=$builder)"
    }
}
