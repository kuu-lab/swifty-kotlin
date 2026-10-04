/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 * Copyright (C) 2019 Square, Inc. Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-io core/common/src/RealSource.kt (tag 0.9.1). `@JvmField` is dropped
 * (this compiler has a single non-JVM target).
 */
package kotlinx.io

internal class RealSource(
    val source: RawSource
) : Source {
    var closed: Boolean = false
    private val bufferField = Buffer()

    @InternalIoApi
    override val buffer: Buffer
        get() = bufferField

    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        checkNotClosed()
        checkByteCount(byteCount)

        if (bufferField.size == 0L) {
            val read = source.readAtMostTo(bufferField, Segment.SIZE.toLong())
            if (read == -1L) return -1L
        }

        val toRead = minOf(byteCount, bufferField.size)
        return bufferField.readAtMostTo(sink, toRead)
    }

    override fun exhausted(): Boolean {
        checkNotClosed()
        return bufferField.exhausted() && source.readAtMostTo(bufferField, Segment.SIZE.toLong()) == -1L
    }

    override fun require(byteCount: Long) {
        if (!request(byteCount)) throw EOFException("Source doesn't contain required number of bytes ($byteCount).")
    }

    override fun request(byteCount: Long): Boolean {
        checkNotClosed()
        checkByteCount(byteCount)
        while (bufferField.size < byteCount) {
            if (source.readAtMostTo(bufferField, Segment.SIZE.toLong()) == -1L) return false
        }
        return true
    }

    override fun readByte(): Byte {
        require(1)
        return bufferField.readByte()
    }

    override fun readAtMostTo(sink: ByteArray, startIndex: Int, endIndex: Int): Int {
        checkBounds(sink.size, startIndex, endIndex)

        if (bufferField.size == 0L) {
            val read = source.readAtMostTo(bufferField, Segment.SIZE.toLong())
            if (read == -1L) return -1
        }
        val toRead = minOf(endIndex - startIndex, bufferField.size).toInt()
        return bufferField.readAtMostTo(sink, startIndex, startIndex + toRead)
    }

    override fun readTo(sink: RawSink, byteCount: Long) {
        try {
            require(byteCount)
        } catch (e: EOFException) {
            // The underlying source is exhausted. Copy the bytes we got before rethrowing.
            sink.write(bufferField, bufferField.size)
            throw e
        }
        bufferField.readTo(sink, byteCount)
    }

    override fun transferTo(sink: RawSink): Long {
        var totalBytesWritten: Long = 0
        while (source.readAtMostTo(bufferField, Segment.SIZE.toLong()) != -1L) {
            val emitByteCount = bufferField.completeSegmentByteCount()
            if (emitByteCount > 0L) {
                totalBytesWritten += emitByteCount
                sink.write(bufferField, emitByteCount)
            }
        }
        if (bufferField.size > 0L) {
            totalBytesWritten += bufferField.size
            sink.write(bufferField, bufferField.size)
        }
        return totalBytesWritten
    }

    override fun readShort(): Short {
        require(2)
        return bufferField.readShort()
    }

    override fun readInt(): Int {
        require(4)
        return bufferField.readInt()
    }

    override fun readLong(): Long {
        require(8)
        return bufferField.readLong()
    }

    override fun skip(byteCount: Long) {
        checkNotClosed()
        checkByteCount(byteCount)
        var remainingByteCount = byteCount
        while (remainingByteCount > 0) {
            if (bufferField.size == 0L && source.readAtMostTo(bufferField, Segment.SIZE.toLong()) == -1L) {
                throw EOFException(
                    "Source exhausted before skipping $byteCount bytes " +
                            "(only ${remainingByteCount - byteCount} bytes were skipped)."
                )
            }
            val toSkip = minOf(remainingByteCount, bufferField.size)
            bufferField.skip(toSkip)
            remainingByteCount -= toSkip
        }
    }

    override fun peek(): Source {
        checkNotClosed()
        return PeekSource(this).buffered()
    }

    override fun close() {
        if (closed) return
        closed = true
        source.close()
        bufferField.clear()
    }

    override fun toString(): String = "buffered($source)"

    @Suppress("NOTHING_TO_INLINE")
    private inline fun checkNotClosed() {
        check(!closed) { "Source is closed." }
    }
}
