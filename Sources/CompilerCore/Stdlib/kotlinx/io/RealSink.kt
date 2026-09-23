/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/RealSink.kt (tag 0.9.1). `hintEmit` approximates
 * upstream's "flush complete segments, keep the trailing partial one" behavior using a fixed-size
 * threshold instead of real segment boundaries (see the note in Buffer.kt).
 */
package kotlinx.io

internal class RealSink(private val sink: RawSink) : Sink {
    private var closed: Boolean = false
    private val bufferField = Buffer()

    override val buffer: Buffer
        get() = bufferField

    private fun checkNotClosed() {
        if (closed) {
            throw IllegalStateException("Sink is closed.")
        }
    }

    override fun write(source: Buffer, byteCount: Long) {
        checkNotClosed()
        if (byteCount < 0L) {
            throw IllegalArgumentException("byteCount: $byteCount")
        }
        bufferField.write(source, byteCount)
        hintEmit()
    }

    override fun write(source: ByteArray, startIndex: Int, endIndex: Int) {
        checkNotClosed()
        checkBounds(source.size, startIndex, endIndex)
        bufferField.write(source, startIndex, endIndex)
        hintEmit()
    }

    override fun transferFrom(source: RawSource): Long {
        checkNotClosed()
        var total = 0L
        while (true) {
            val read = source.readAtMostTo(bufferField, SEGMENT_SIZE_HINT.toLong())
            if (read == -1L) {
                return total
            }
            total += read
            hintEmit()
        }
    }

    override fun write(source: RawSource, byteCount: Long) {
        checkNotClosed()
        if (byteCount < 0L) {
            throw IllegalArgumentException("byteCount: $byteCount")
        }
        var remaining = byteCount
        while (remaining > 0L) {
            val read = source.readAtMostTo(bufferField, remaining)
            if (read == -1L) {
                val bytesRead = byteCount - remaining
                throw EOFException(
                    "Source exhausted before reading $byteCount bytes from it (number of bytes read: $bytesRead)."
                )
            }
            remaining -= read
            hintEmit()
        }
    }

    override fun writeByte(byte: Byte) {
        checkNotClosed()
        bufferField.writeByte(byte)
        hintEmit()
    }

    override fun writeShort(short: Short) {
        checkNotClosed()
        bufferField.writeShort(short)
        hintEmit()
    }

    override fun writeInt(int: Int) {
        checkNotClosed()
        bufferField.writeInt(int)
        hintEmit()
    }

    override fun writeLong(long: Long) {
        checkNotClosed()
        bufferField.writeLong(long)
        hintEmit()
    }

    override fun hintEmit() {
        checkNotClosed()
        val size = bufferField.size
        val hint = SEGMENT_SIZE_HINT.toLong()
        if (size >= hint) {
            val toFlush = (size / hint) * hint
            if (toFlush > 0L) {
                sink.write(bufferField, toFlush)
            }
        }
    }

    override fun emit() {
        checkNotClosed()
        val byteCount = bufferField.size
        if (byteCount > 0L) {
            sink.write(bufferField, byteCount)
        }
    }

    override fun flush() {
        checkNotClosed()
        if (bufferField.size > 0L) {
            sink.write(bufferField, bufferField.size)
        }
        sink.flush()
    }

    override fun close() {
        if (closed) {
            return
        }
        var thrown: Throwable? = null
        try {
            if (bufferField.size > 0L) {
                sink.write(bufferField, bufferField.size)
            }
        } catch (e: Throwable) {
            thrown = e
        }
        try {
            sink.close()
        } catch (e: Throwable) {
            if (thrown == null) {
                thrown = e
            }
        }
        closed = true
        val toRethrow = thrown
        if (toRethrow != null) {
            throw toRethrow
        }
    }

    override fun toString(): String = "buffered($sink)"
}
