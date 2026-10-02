/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/Source.kt (tag 0.9.1).
 * kotlinx-io declares this `sealed`, and several members take default parameter values; both are
 * dropped here (no code exhaustively `when`s over Source, and default values on interface members
 * are not dispatched correctly through an override on this compiler yet). The default-taking forms
 * are provided as extension functions in SourceSinkExtensions.kt instead.
 */
package kotlinx.io

/**
 * A source that facilitates typed data reads and keeps a buffer internally so that callers can read
 * chunks of data without requesting it from a downstream on every call.
 */
public interface Source : RawSource {
    public val buffer: Buffer

    /**
     * Returns true if there are no more bytes in this source.
     */
    public fun exhausted(): Boolean

    /**
     * Attempts to fill the buffer with at least [byteCount] bytes of data from the underlying source
     * and throws [EOFException] when the source is exhausted before fulfilling the requirement.
     */
    public fun require(byteCount: Long)

    /**
     * Attempts to fill the buffer with at least [byteCount] bytes of data from the underlying source
     * and returns a value indicating if the requirement was successfully fulfilled.
     */
    public fun request(byteCount: Long): Boolean

    /**
     * Removes a byte from this source and returns it.
     */
    public fun readByte(): Byte

    /**
     * Removes two bytes from this source and returns a short composed of them in big-endian order.
     */
    public fun readShort(): Short

    /**
     * Removes four bytes from this source and returns an int composed of them in big-endian order.
     */
    public fun readInt(): Int

    /**
     * Removes eight bytes from this source and returns a long composed of them in big-endian order.
     */
    public fun readLong(): Long

    /**
     * Reads and discards [byteCount] bytes from this source.
     */
    public fun skip(byteCount: Long)

    /**
     * Removes up to `endIndex - startIndex` bytes from this source, copies them into [sink]'s
     * subrange starting at [startIndex] and ending at [endIndex], and returns the number of bytes
     * read, or -1 if this source is exhausted.
     */
    public fun readAtMostTo(sink: ByteArray, startIndex: Int, endIndex: Int): Int

    /**
     * Removes exactly [byteCount] bytes from this source and writes them to [sink].
     */
    public fun readTo(sink: RawSink, byteCount: Long)

    /**
     * Removes all bytes from this source, writes them to [sink], and returns the total number of
     * bytes written to [sink].
     */
    public fun transferTo(sink: RawSink): Long

    /**
     * Returns a new [Source] that can read data from this source without consuming it.
     */
    public fun peek(): Source
}
