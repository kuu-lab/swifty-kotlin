/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/common/src/Sink.kt (tag 0.9.1).
 * See the note in Source.kt about dropping `sealed` and interface-level default parameter values.
 */
package kotlinx.io

/**
 * A sink that facilitates typed data writes and keeps a buffer internally so that callers can write
 * some data without sending it directly to an upstream.
 */
public interface Sink : RawSink {
    public val buffer: Buffer

    /**
     * Writes bytes from [source]'s subrange starting at [startIndex] and ending at [endIndex] to
     * this sink.
     */
    public fun write(source: ByteArray, startIndex: Int, endIndex: Int)

    /**
     * Removes all bytes from [source] and writes them to this sink. Returns the number of bytes
     * read, which will be 0 if [source] is exhausted.
     */
    public fun transferFrom(source: RawSource): Long

    /**
     * Removes [byteCount] bytes from [source] and writes them to this sink.
     */
    public fun write(source: RawSource, byteCount: Long)

    /**
     * Writes a byte to this sink.
     */
    public fun writeByte(byte: Byte)

    /**
     * Writes two bytes containing [short], in big-endian order, to this sink.
     */
    public fun writeShort(short: Short)

    /**
     * Writes four bytes containing [int], in big-endian order, to this sink.
     */
    public fun writeInt(int: Int)

    /**
     * Writes eight bytes containing [long], in big-endian order, to this sink.
     */
    public fun writeLong(long: Long)

    /**
     * Writes all buffered data to the underlying sink, if one exists, then explicitly flushes it.
     */
    override fun flush()

    /**
     * Writes all buffered data to the underlying sink if one exists, without flushing it.
     */
    public fun emit()

    /**
     * Hints that the buffer may be partially emitted to the underlying sink.
     */
    public fun hintEmit()
}
