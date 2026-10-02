/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/Buffer.kt (tag 0.9.1), simplified for this compiler:
 * upstream stores bytes as a doubly-linked list of pooled `Segment`s to avoid copies when data
 * moves between buffers. This port instead uses a single growable `ByteArray` with `start`/`end`
 * cursors. Observable behavior (values read/written, thrown exceptions, `size`) is preserved;
 * internal memory reuse across buffers is not. `Segment`/`SegmentPool`/`UnsafeBufferOperations` are
 * intentionally not ported in this pass (see docs/spec.md and the kotlinx.io tracking note).
 */
package kotlinx.io

internal const val SEGMENT_SIZE_HINT: Int = 8192

internal fun checkByteCount(byteCount: Long) {
    if (byteCount < 0L) {
        throw IllegalArgumentException("byteCount ($byteCount) < 0")
    }
}

internal fun checkBounds(size: Int, startIndex: Int, endIndex: Int) {
    if (startIndex < 0 || endIndex > size) {
        throw IndexOutOfBoundsException(
            "startIndex ($startIndex) and endIndex ($endIndex) are not within the range [0..size($size))"
        )
    }
    if (startIndex > endIndex) {
        throw IllegalArgumentException("startIndex ($startIndex) > endIndex ($endIndex)")
    }
}

internal fun checkBounds(size: Long, startIndex: Long, endIndex: Long) {
    if (startIndex < 0L || endIndex > size) {
        throw IndexOutOfBoundsException(
            "startIndex ($startIndex) and endIndex ($endIndex) are not within the range [0..size($size))"
        )
    }
    if (startIndex > endIndex) {
        throw IllegalArgumentException("startIndex ($startIndex) > endIndex ($endIndex)")
    }
}

internal fun checkOffsetAndCount(size: Long, offset: Long, byteCount: Long) {
    if (offset < 0L || offset > size || size - offset < byteCount || byteCount < 0L) {
        throw IllegalArgumentException(
            "offset ($offset) and byteCount ($byteCount) are not within the range [0..size($size))"
        )
    }
}

/**
 * A collection of bytes in memory.
 *
 * [Buffer] implements both [Source] and [Sink] and can be used as either, but unlike regular sinks
 * and sources its [close], [flush], [emit], [hintEmit] do not affect the buffer's state, and
 * [exhausted] only indicates that the buffer is empty.
 */
public class Buffer : Source, Sink {
    internal var data: ByteArray = ByteArray(0)
    internal var start: Int = 0
    internal var end: Int = 0

    public val size: Long
        get() = (end - start).toLong()

    override val buffer: Buffer
        get() = this

    private fun ensureCapacity(additional: Int) {
        if (end + additional <= data.size) {
            return
        }
        val currentSize = end - start
        var newCapacity = if (data.size == 0) 64 else data.size
        while (newCapacity < currentSize + additional) {
            newCapacity = newCapacity * 2
        }
        val newData = ByteArray(newCapacity)
        var i = 0
        while (i < currentSize) {
            newData[i] = data[start + i]
            i += 1
        }
        data = newData
        start = 0
        end = currentSize
    }

    private fun recycleIfEmpty() {
        if (start == end) {
            start = 0
            end = 0
        }
    }

    override fun exhausted(): Boolean = start == end

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
        if (start == end) {
            throw EOFException("Buffer doesn't contain required number of bytes (size: 0, required: 1)")
        }
        val v = data[start]
        start += 1
        recycleIfEmpty()
        return v
    }

    override fun readShort(): Short {
        require(2)
        var result = 0
        var i = 0
        while (i < 2) {
            result = (result shl 8) or (data[start + i].toInt() and 0xff)
            i += 1
        }
        start += 2
        recycleIfEmpty()
        return result.toShort()
    }

    override fun readInt(): Int {
        require(4)
        var result = 0
        var i = 0
        while (i < 4) {
            result = (result shl 8) or (data[start + i].toInt() and 0xff)
            i += 1
        }
        start += 4
        recycleIfEmpty()
        return result
    }

    override fun readLong(): Long {
        require(8)
        var result = 0L
        var i = 0
        while (i < 8) {
            result = (result shl 8) or (data[start + i].toLong() and 0xffL)
            i += 1
        }
        start += 8
        recycleIfEmpty()
        return result
    }

    override fun skip(byteCount: Long) {
        if (byteCount < 0L) {
            throw IllegalArgumentException("byteCount: $byteCount")
        }
        if (byteCount > size) {
            throw EOFException("Buffer exhausted before skipping $byteCount bytes.")
        }
        start += byteCount.toInt()
        recycleIfEmpty()
    }

    public fun clear() {
        start = 0
        end = 0
    }

    public operator fun get(position: Long): Byte {
        if (position < 0L || position >= size) {
            throw IndexOutOfBoundsException("position ($position) is not within the range [0..size($size))")
        }
        return data[start + position.toInt()]
    }

    public fun indexOf(byte: Byte, startIndex: Long = 0L, endIndex: Long = size): Long {
        val endOffset = if (endIndex > size) size else endIndex
        checkBounds(size, startIndex, endOffset)
        var i = startIndex
        while (i < endOffset) {
            if (data[start + i.toInt()] == byte) {
                return i
            }
            i += 1L
        }
        return -1L
    }

    public fun copyTo(out: Buffer, startIndex: Long = 0L, endIndex: Long = size) {
        checkBounds(size, startIndex, endIndex)
        val count = (endIndex - startIndex).toInt()
        if (count == 0) {
            return
        }
        out.ensureCapacity(count)
        var i = 0
        while (i < count) {
            out.data[out.end + i] = data[start + startIndex.toInt() + i]
            i += 1
        }
        out.end += count
    }

    public fun copy(): Buffer {
        val result = Buffer()
        val n = end - start
        if (n == 0) {
            return result
        }
        result.ensureCapacity(n)
        var i = 0
        while (i < n) {
            result.data[i] = data[start + i]
            i += 1
        }
        result.end = n
        return result
    }

    override fun readAtMostTo(sink: ByteArray, startIndex: Int, endIndex: Int): Int {
        checkBounds(sink.size, startIndex, endIndex)
        if (start == end) {
            return -1
        }
        val available = end - start
        val requested = endIndex - startIndex
        val toCopy = if (requested < available) requested else available
        var i = 0
        while (i < toCopy) {
            sink[startIndex + i] = data[start + i]
            i += 1
        }
        start += toCopy
        recycleIfEmpty()
        return toCopy
    }

    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        checkByteCount(byteCount)
        if (size == 0L) {
            return -1L
        }
        val bytesToWrite = if (byteCount > size) size else byteCount
        sink.write(this, bytesToWrite)
        return bytesToWrite
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
        val byteCount = size
        if (byteCount > 0L) {
            sink.write(this, byteCount)
        }
        return byteCount
    }

    override fun transferFrom(source: RawSource): Long {
        var total = 0L
        while (true) {
            val read = source.readAtMostTo(this, SEGMENT_SIZE_HINT.toLong())
            if (read == -1L) {
                return total
            }
            total += read
        }
    }

    override fun peek(): Source = PeekSource(this).buffered()

    override fun write(source: ByteArray, startIndex: Int, endIndex: Int) {
        checkBounds(source.size, startIndex, endIndex)
        val count = endIndex - startIndex
        if (count == 0) {
            return
        }
        ensureCapacity(count)
        var i = 0
        while (i < count) {
            data[end + i] = source[startIndex + i]
            i += 1
        }
        end += count
    }

    override fun write(source: RawSource, byteCount: Long) {
        checkByteCount(byteCount)
        var remaining = byteCount
        while (remaining > 0L) {
            val read = source.readAtMostTo(this, remaining)
            if (read == -1L) {
                throw EOFException(
                    "Source exhausted before reading $byteCount bytes. Only ${byteCount - remaining} were read."
                )
            }
            remaining -= read
        }
    }

    override fun write(source: Buffer, byteCount: Long) {
        if (source === this) {
            throw IllegalArgumentException("source == this")
        }
        checkOffsetAndCount(source.size, 0L, byteCount)
        val n = byteCount.toInt()
        if (n > 0) {
            ensureCapacity(n)
            var i = 0
            while (i < n) {
                data[end + i] = source.data[source.start + i]
                i += 1
            }
            end += n
        }
        source.start += n
        source.recycleIfEmpty()
    }

    override fun writeByte(byte: Byte) {
        ensureCapacity(1)
        data[end] = byte
        end += 1
    }

    override fun writeShort(short: Short) {
        ensureCapacity(2)
        val v = short.toInt()
        data[end] = ((v shr 8) and 0xff).toByte()
        data[end + 1] = (v and 0xff).toByte()
        end += 2
    }

    override fun writeInt(int: Int) {
        ensureCapacity(4)
        data[end] = ((int shr 24) and 0xff).toByte()
        data[end + 1] = ((int shr 16) and 0xff).toByte()
        data[end + 2] = ((int shr 8) and 0xff).toByte()
        data[end + 3] = (int and 0xff).toByte()
        end += 4
    }

    override fun writeLong(long: Long) {
        ensureCapacity(8)
        data[end] = ((long shr 56) and 0xffL).toByte()
        data[end + 1] = ((long shr 48) and 0xffL).toByte()
        data[end + 2] = ((long shr 40) and 0xffL).toByte()
        data[end + 3] = ((long shr 32) and 0xffL).toByte()
        data[end + 4] = ((long shr 24) and 0xffL).toByte()
        data[end + 5] = ((long shr 16) and 0xffL).toByte()
        data[end + 6] = ((long shr 8) and 0xffL).toByte()
        data[end + 7] = (long and 0xffL).toByte()
        end += 8
    }

    override fun hintEmit() {
    }

    override fun emit() {
    }

    override fun flush() {
    }

    override fun close() {
    }

    override fun toString(): String {
        if (size == 0L) {
            return "Buffer(size=0)"
        }
        val maxPrintable = 64L
        val len = if (size < maxPrintable) size.toInt() else maxPrintable.toInt()
        val hexChars = charArrayOf('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f')
        val builder = StringBuilder()
        var i = 0
        while (i < len) {
            val b = data[start + i].toInt() and 0xff
            builder.append(hexChars[(b shr 4) and 0xf])
            builder.append(hexChars[b and 0xf])
            i += 1
        }
        if (size > maxPrintable) {
            builder.append('…')
        }
        return "Buffer(size=$size hex=$builder)"
    }
}
