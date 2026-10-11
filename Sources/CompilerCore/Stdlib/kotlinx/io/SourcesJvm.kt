/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 */

/*
 * Copyright (C) 2014 Square, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package kotlinx.io

import kotlinx.io.unsafe.UnsafeBufferOperations
import java.io.EOFException
import java.io.InputStream
import java.nio.charset.Charset

@OptIn(UnsafeIoApi::class)
private fun Buffer.readStringImpl(byteCount: Long, charset: Charset): String {
    require(byteCount >= 0 && byteCount <= Int.MAX_VALUE) {
        "byteCount ($byteCount) is not within the range [0..${Int.MAX_VALUE})"
    }
    if (size < byteCount) {
        throw EOFException("Buffer contains less bytes then required (byteCount: $byteCount, size: $size)")
    }
    if (byteCount == 0L) return ""

    var result: String? = null
    val _ = UnsafeBufferOperations.readFromHead(this) { data, pos, limit ->
        val len = limit - pos
        if (len >= byteCount) {
            result = String(data, pos, byteCount.toInt(), charset)
            byteCount.toInt()
        } else {
            0
        }
    }
    return result ?: String(readByteArray(byteCount.toInt()), charset)
}

/**
 * Decodes whole content of this stream into a string using [charset]. Returns empty string if the source is exhausted.
 *
 * @param charset the [Charset] to use for string decoding.
 *
 * @throws IllegalStateException when the source is closed.
 * @throws IOException when some I/O error occurs.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.readWriteStrings
 */
@OptIn(InternalIoApi::class)
public fun Source.readString(charset: Charset): String {
    var req = 1L
    while (request(req)) {
        req *= 2
    }
    return buffer.readStringImpl(buffer.size, charset)
}

/**
 * Decodes [byteCount] bytes of this stream into a string using [charset].
 *
 * @param byteCount the number of bytes to read from the source for decoding.
 * @param charset the [Charset] to use for string decoding.
 *
 * @throws EOFException when the source exhausted before [byteCount] bytes could be read from it.
 * @throws IllegalStateException when the source is closed.
 * @throws IllegalArgumentException if [byteCount] is negative or its value is greater than [Int.MAX_VALUE].
 * @throws IOException when some I/O error occurs.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.readStringBounded
 */
@OptIn(InternalIoApi::class)
public fun Source.readString(byteCount: Long, charset: Charset): String {
    require(byteCount)
    return buffer.readStringImpl(byteCount, charset)
}

/**
 * Returns an input stream that reads from this source. Closing the stream will also close this source.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.asStream
 */
@OptIn(InternalIoApi::class)
public fun Source.asInputStream(): InputStream {
    val isClosed: () -> Boolean = when (this) {
        is RealSource -> this::closed
        is Buffer -> {
            { false }
        }
    }

    return kkKotlinSourceInputStream(
        {
            if (isClosed()) throw IOException("Underlying source is closed.")
            if (exhausted()) -1 else readByte().toInt() and 0xff
        },
        { data: ByteArray, offset: Int, byteCount: Int ->
            if (isClosed()) throw IOException("Underlying source is closed.")
            checkOffsetAndCount(data.size.toLong(), offset.toLong(), byteCount.toLong())
            this.readAtMostTo(data, offset, offset + byteCount)
        },
        {
            if (isClosed()) throw IOException("Underlying source is closed.")
            minOf(buffer.size, Int.MAX_VALUE.toLong()).toInt()
        },
        { close() },
        { "${this}.asInputStream()" }
    )
}

@kotlin.internal.KsSymbolName("__kk_kotlin_source_input_stream")
private external fun kkKotlinSourceInputStream(
    readByte: () -> Int,
    readBytes: (ByteArray, Int, Int) -> Int,
    available: () -> Int,
    close: () -> Unit,
    description: () -> String
): InputStream
