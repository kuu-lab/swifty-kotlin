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

import java.nio.ByteBuffer
import java.nio.channels.ReadableByteChannel

/**
 * Reads at most [ByteBuffer.remaining] bytes from this source into [sink] and returns the number of bytes read.
 *
 * @param sink the sink to write the data to.
 *
 * @throws IllegalStateException when the source is closed.
 * @throws IOException when some I/O error occurs.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.readWriteByteBuffer
 */
@OptIn(InternalIoApi::class)
public fun Source.readAtMostTo(sink: ByteBuffer): Int {
    if (buffer.size == 0L) {
        val _ = request(Segment.SIZE.toLong())
        if (buffer.size == 0L) return -1
    }

    return buffer.readAtMostTo(sink)
}

/**
 * Returns [ReadableByteChannel] backed by this source. Closing the source will close the source.
 */
public fun Source.asByteChannel(): ReadableByteChannel {
    val isClosed: () -> Boolean = when (this) {
        is RealSource -> this::closed
        is Buffer -> {
            { false }
        }
    }

    return object : ReadableByteChannel {
        override fun close() {
            this@asByteChannel.close()
        }

        override fun isOpen(): Boolean = !isClosed()

        override fun read(sink: ByteBuffer): Int = this@asByteChannel.readAtMostTo(sink)
    }
}
