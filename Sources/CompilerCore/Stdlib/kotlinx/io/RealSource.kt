/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/RealSource.kt (tag 0.9.1), adjusted for the single
 * growable-ByteArray `Buffer` used by this port (see the note in Buffer.kt).
 */
package kotlinx.io

internal class RealSource(private val source: RawSource) : Source {
    private var closed: Boolean = false
    private val bufferField = Buffer()

    override val buffer: Buffer
        get() = bufferField

    private fun checkNotClosed() {
        if (closed) {
            throw IllegalStateException("Source is closed.")
        }
    }

    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        checkNotClosed()
        checkByteCount(byteCount)
        if (bufferField.size == 0L) {
            val read = source.readAtMostTo(bufferField, SEGMENT_SIZE_HINT.toLong())
            if (read == -1L) {
                return -1L
            }
        }
        val toRead = if (byteCount < bufferField.size) byteCount else bufferField.size
        return bufferField.readAtMostTo(sink, toRead)
    }

    override fun exhausted(): Boolean {
        checkNotClosed()
        if (!bufferField.exhausted()) {
            return false
        }
        return source.readAtMostTo(bufferField, SEGMENT_SIZE_HINT.toLong()) == -1L
    }

    override fun require(byteCount: Long) {
        if (!request(byteCount)) {
            throw EOFException("Source doesn't contain required number of bytes ($byteCount).")
        }
    }

    override fun request(byteCount: Long): Boolean {
        checkNotClosed()
        if (byteCount < 0L) {
            throw IllegalArgumentException("byteCount: $byteCount")
        }
        while (bufferField.size < byteCount) {
            if (source.readAtMostTo(bufferField, SEGMENT_SIZE_HINT.toLong()) == -1L) {
                return false
            }
        }
        return true
    }

    override fun readByte(): Byte {
        require(1)
        return bufferField.readByte()
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

    override fun readAtMostTo(sink: ByteArray, startIndex: Int, endIndex: Int): Int {
        checkBounds(sink.size, startIndex, endIndex)
        if (bufferField.size == 0L) {
            val read = source.readAtMostTo(bufferField, SEGMENT_SIZE_HINT.toLong())
            if (read == -1L) {
                return -1
            }
        }
        val requested = endIndex - startIndex
        val toRead = if (requested.toLong() < bufferField.size) requested else bufferField.size.toInt()
        return bufferField.readAtMostTo(sink, startIndex, startIndex + toRead)
    }

    override fun readTo(sink: RawSink, byteCount: Long) {
        try {
            require(byteCount)
        } catch (e: EOFException) {
            sink.write(bufferField, bufferField.size)
            throw e
        }
        bufferField.readTo(sink, byteCount)
    }

    override fun transferTo(sink: RawSink): Long {
        var total = 0L
        while (source.readAtMostTo(bufferField, SEGMENT_SIZE_HINT.toLong()) != -1L) {
            val emitByteCount = bufferField.size
            if (emitByteCount > 0L) {
                total += emitByteCount
                sink.write(bufferField, emitByteCount)
            }
        }
        if (bufferField.size > 0L) {
            total += bufferField.size
            sink.write(bufferField, bufferField.size)
        }
        return total
    }

    override fun skip(byteCount: Long) {
        checkNotClosed()
        if (byteCount < 0L) {
            throw IllegalArgumentException("byteCount: $byteCount")
        }
        var remaining = byteCount
        while (remaining > 0L) {
            if (bufferField.size == 0L && source.readAtMostTo(bufferField, SEGMENT_SIZE_HINT.toLong()) == -1L) {
                throw EOFException(
                    "Source exhausted before skipping $byteCount bytes (only ${byteCount - remaining} bytes were skipped)."
                )
            }
            val toSkip = if (remaining < bufferField.size) remaining else bufferField.size
            bufferField.skip(toSkip)
            remaining -= toSkip
        }
    }

    override fun peek(): Source {
        checkNotClosed()
        return PeekSource(this).buffered()
    }

    override fun close() {
        if (closed) {
            return
        }
        closed = true
        source.close()
        bufferField.clear()
    }

    override fun toString(): String = "buffered($source)"
}
