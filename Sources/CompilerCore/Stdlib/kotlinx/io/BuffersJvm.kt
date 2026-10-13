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
import kotlinx.io.unsafe.withData
import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream

/**
 * Reads and exhausts bytes from [input] into this buffer. Stops reading data on [input] exhaustion.
 *
 * @param input the stream to read data from.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.bufferTransferToStream
 */
@IgnorableReturnValue
public fun Buffer.transferFrom(input: InputStream): Buffer {
    write(input, Long.MAX_VALUE, true)
    return this
}

/**
 * Reads [byteCount] bytes from [input] into this buffer. Throws an exception when [input] is
 * exhausted before reading [byteCount] bytes.
 *
 * @param input the stream to read data from.
 * @param byteCount the number of bytes read from [input].
 *
 * @throws IOException when [input] exhausted before reading [byteCount] bytes from it.
 * @throws IllegalArgumentException when [byteCount] is negative.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.writeInputStreamToBuffer
 */
@IgnorableReturnValue
public fun Buffer.write(input: InputStream, byteCount: Long): Buffer {
    checkByteCount(byteCount)
    write(input, byteCount, false)
    return this
}

@OptIn(UnsafeIoApi::class)
private fun Buffer.write(input: InputStream, byteCount: Long, forever: Boolean) {
    var remainingByteCount = byteCount
    var exhausted = false
    while (!exhausted && (remainingByteCount > 0L || forever)) {
        val _ = UnsafeBufferOperations.writeToTail(this, 1) { data, pos, limit ->
            val maxToCopy = minOf(remainingByteCount, limit - pos).toInt()
            val bytesRead = input.read(data, pos, maxToCopy)
            if (bytesRead == -1) {
                if (!forever) {
                    throw EOFException("Stream exhausted before $byteCount bytes were read.")
                }
                exhausted = true
                0
            } else {
                remainingByteCount -= bytesRead
                bytesRead
            }
        }
    }
}

/**
 * Consumes [byteCount] bytes from this buffer and writes it to [out].
 *
 * @param out the [OutputStream] to write to.
 * @param byteCount the number of bytes to be written, [Buffer.size] by default.
 *
 * @throws IllegalArgumentException when [byteCount] is negative or exceeds the buffer size.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.bufferTransferToStream
 */
@OptIn(UnsafeIoApi::class)
public fun Buffer.readTo(out: OutputStream, byteCount: Long = size) {
    checkOffsetAndCount(size, 0, byteCount)
    var remainingByteCount = byteCount

    while (remainingByteCount > 0L) {
        remainingByteCount -= UnsafeBufferOperations.readFromHead(this) { data, pos, limit ->
            val toCopy = minOf(remainingByteCount, limit - pos).toInt()
            out.write(data, pos, toCopy)
            toCopy
        }
    }
}

/**
 * Copies bytes from this buffer's subrange, starting at [startIndex] and ending at [endIndex], to [out]. This method
 * does not consume data from the buffer.
 *
 * @param out the destination to copy data into.
 * @param startIndex the index (inclusive) of the first byte to copy, `0` by default.
 * @param endIndex the index (exclusive) of the last byte to copy, `buffer.size` by default.
 *
 * @throws IndexOutOfBoundsException when [startIndex] or [endIndex] is out of this buffer bounds (`[0..buffer.size)`).
 * @throws IllegalArgumentException when `startIndex > endIndex`.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.copyBufferToOutputStream
 */
@OptIn(UnsafeIoApi::class)
public fun Buffer.copyTo(
    out: OutputStream,
    startIndex: Long = 0L,
    endIndex: Long = size
) {
    checkBounds(size, startIndex, endIndex)
    if (startIndex == endIndex) return

    var remainingByteCount = endIndex - startIndex

    UnsafeBufferOperations.iterate(this, startIndex) { ctx, seg, segOffset ->
        var curr = seg!!
        var currentOffset = (startIndex - segOffset).toInt()
        while (remainingByteCount > 0) {
            ctx.withData(curr) { data, pos, limit ->
                val toCopy = minOf(limit - pos - currentOffset, remainingByteCount).toInt()
                out.write(data, pos + currentOffset, toCopy)
                remainingByteCount -= toCopy
            }
            curr = ctx.next(curr) ?: break
            currentOffset = 0
        }
    }
}
