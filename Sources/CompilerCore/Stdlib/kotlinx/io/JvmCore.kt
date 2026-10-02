/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 *
 * Derived from kotlinx-io core/jvm/src/JvmCore.kt (tag 0.9.1). The java.io types are backed by
 * this compiler's synthetic `java.io` stream stubs rather than real JVM streams, so bulk
 * transfers go through `InputStream.read()`/`OutputStream.write(Int)` per byte instead of
 * `UnsafeBufferOperations` segment access.
 */
package kotlinx.io

import java.io.InputStream
import java.io.OutputStream

/**
 * Returns [RawSink] that writes to an output stream.
 *
 * Use [RawSink.buffered] to create a buffered sink from it.
 */
public fun OutputStream.asSink(): RawSink = OutputStreamSink(this)

private class OutputStreamSink(
    private val out: OutputStream,
) : RawSink {
    override fun write(source: Buffer, byteCount: Long) {
        checkOffsetAndCount(source.size, 0, byteCount)
        // The synthetic OutputStream only exposes single-byte and
        // List<Int>-buffered writes, so a bounded bulk write has to go byte
        // by byte instead of copying segment arrays like upstream.
        var remaining = byteCount
        while (remaining > 0L) {
            out.write(source.readByte().toInt())
            remaining--
        }
    }

    override fun flush() = out.flush()

    override fun close() = out.close()

    override fun toString() = "RawSink($out)"
}

/**
 * Returns [RawSource] that reads from an input stream.
 *
 * Use [RawSource.buffered] to create a buffered source from it.
 */
public fun InputStream.asSource(): RawSource = InputStreamSource(this)

private class InputStreamSource(
    private val input: InputStream,
) : RawSource {
    override fun readAtMostTo(sink: Buffer, byteCount: Long): Long {
        if (byteCount == 0L) return 0L
        checkByteCount(byteCount)
        // The synthetic InputStream only exposes a single-byte read() and a
        // drain-to-end readBytes(), so a bounded bulk read has to go byte by
        // byte instead of filling a tail segment like upstream.
        var bytesRead = 0L
        while (bytesRead < byteCount) {
            val value = input.read()
            if (value < 0) break
            sink.writeByte(value.toByte())
            bytesRead++
        }
        return if (bytesRead == 0L) -1L else bytesRead
    }

    override fun close() = input.close()

    override fun toString() = "RawSource($input)"
}
