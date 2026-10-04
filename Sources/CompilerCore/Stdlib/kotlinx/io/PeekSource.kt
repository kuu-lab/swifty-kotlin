/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/PeekSource.kt (tag 0.9.1). Upstream detects "upstream was
 * read from" by comparing the identity of the buffer's head `Segment` and its read position; this
 * port has no `Segment`, so it compares the upstream buffer's `start` cursor instead.
 */
package kotlinx.io

internal class PeekSource(private val upstream: Source) : RawSource {
    private val buf: Buffer = upstream.buffer
    private var expectedStart: Int = -1
    private var closed: Boolean = false
    private var pos: Long = 0L

    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (closed) {
            throw IllegalStateException("Source is closed.")
        }
        checkByteCount(byteCount)
        if (expectedStart != -1 && expectedStart != buf.start) {
            throw IllegalStateException("Peek source is invalid because upstream source was used")
        }
        if (byteCount == 0L) {
            return 0L
        }
        if (!upstream.request(pos + 1L)) {
            return -1L
        }
        if (expectedStart == -1 && buf.size > 0L) {
            expectedStart = buf.start
        }
        val remaining = buf.size - pos
        val toCopy = if (byteCount < remaining) byteCount else remaining
        buf.copyTo(sink, pos, pos + toCopy)
        pos += toCopy
        return toCopy
    }

    override fun close() {
        closed = true
    }
}
