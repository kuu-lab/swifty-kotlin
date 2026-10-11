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
import java.nio.channels.WritableByteChannel

/**
 * Writes data from the [source] into this sink and returns the number of bytes written.
 *
 * @param source the source to read from.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 *
 * @sample kotlinx.io.samples.KotlinxIoSamplesJvm.readWriteByteBuffer
 */
@OptIn(InternalIoApi::class)
public fun Sink.write(source: ByteBuffer): Int {
    val sizeBefore = buffer.size
    buffer.transferFrom(source)
    val bytesRead = buffer.size - sizeBefore
    hintEmit()
    return bytesRead.toInt()
}

/**
 * Returns [WritableByteChannel] backed by this sink. Closing the channel will also close the sink.
 */
public fun Sink.asByteChannel(): WritableByteChannel {
    val isClosed: () -> Boolean = when (this) {
        is RealSink -> this::closed
        is Buffer -> {
            { false }
        }
    }

    return object : WritableByteChannel {
        override fun close() {
            this@asByteChannel.close()
        }

        override fun isOpen(): Boolean = !isClosed()

        override fun write(source: ByteBuffer): Int {
            check(!isClosed()) { "Underlying sink is closed." }
            return this@asByteChannel.write(source)
        }
    }
}
