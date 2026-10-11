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
import java.nio.ByteBuffer
import java.nio.channels.ByteChannel

/**
 * Writes up to [ByteBuffer.remaining] bytes from this buffer to the sink.
 * Return the number of bytes written.
 *
 * @param sink the sink to write data to.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.readWriteByteBuffer
 */
@OptIn(UnsafeIoApi::class)
public fun Buffer.readAtMostTo(sink: ByteBuffer): Int {
    if (exhausted()) return -1
    val toCopy = UnsafeBufferOperations.readFromHead(this) { data, pos, limit ->
        val toCopy = minOf(sink.remaining(), limit - pos)
        sink.put(data, pos, toCopy)
        toCopy
    }

    return toCopy
}

/**
 * Reads all data from [source] into this buffer.
 *
 * @return this buffer.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.transferBufferFromByteBuffer
 */
@IgnorableReturnValue
@OptIn(UnsafeIoApi::class)
public fun Buffer.transferFrom(source: ByteBuffer): Buffer {
    val byteCount = source.remaining()
    var remaining = byteCount

    while (remaining > 0) {
        remaining -= UnsafeBufferOperations.writeToTail(this, 1) { data, pos, limit ->
            val toCopy = minOf(remaining, limit - pos)
            source.get(data, pos, toCopy)
            toCopy
        }
    }

    return this
}

/**
 * Returns a new [ByteChannel] instance representing this buffer.
 */
public fun Buffer.asByteChannel(): ByteChannel = object : ByteChannel {
    override fun read(sink: ByteBuffer): Int = readAtMostTo(sink)

    override fun write(source: ByteBuffer): Int {
        val sizeBefore = size
        transferFrom(source)
        return (size - sizeBefore).toInt()
    }

    override fun close() {}

    override fun isOpen(): Boolean = true
}
