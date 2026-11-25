/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE.txt file.
 */

package kotlinx.io.unsafe

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind.EXACTLY_ONCE
import kotlin.contracts.contract
import kotlinx.io.Buffer
import kotlinx.io.Segment
import kotlinx.io.UnsafeIoApi
import kotlinx.io.unsafe.UnsafeBufferOperations.maxSafeWriteCapacity
import java.nio.ByteBuffer

@UnsafeIoApi
@OptIn(ExperimentalContracts::class)
public inline fun UnsafeBufferOperations.readFromHead(buffer: Buffer, readAction: (ByteBuffer) -> Unit): Int {
    contract {
        callsInPlace(readAction, EXACTLY_ONCE)
    }
    return readFromHead(buffer) { rawData, pos, limit ->
        val bb = ByteBuffer.wrap(rawData, pos, limit - pos).slice().asReadOnlyBuffer()
        readAction(bb)
        bb.position()
    }
}

@UnsafeIoApi
@OptIn(ExperimentalContracts::class)
public inline fun UnsafeBufferOperations.writeToTail(
    buffer: Buffer,
    minimumCapacity: Int,
    writeAction: (ByteBuffer) -> Unit
): Int {
    contract {
        callsInPlace(writeAction, EXACTLY_ONCE)
    }
    return writeToTail(buffer, minimumCapacity) { rawData, pos, limit ->
        val bb = ByteBuffer.wrap(rawData, pos, limit - pos).slice()
        writeAction(bb)
        bb.position()
    }
}

@UnsafeIoApi
@OptIn(ExperimentalContracts::class)
public inline fun UnsafeBufferOperations.readBulk(
    buffer: Buffer,
    iovec: Array<ByteBuffer?>,
    readAction: (iovec: Array<ByteBuffer?>, iovecSize: Int) -> Long
): Long {
    contract {
        callsInPlace(readAction, EXACTLY_ONCE)
    }

    val head = buffer.head ?: throw IllegalArgumentException("buffer is empty.")
    if (iovec.isEmpty()) throw IllegalArgumentException("iovec is empty.")

    var currentSegment: Segment = head
    var idx = 0
    var capacity = 0L
    do {
        val pos = currentSegment.pos
        val limit = currentSegment.limit
        val len = limit - pos
        iovec[idx++] = ByteBuffer.wrap(currentSegment.dataAsByteArray(true), pos, len)
            .slice()
            .asReadOnlyBuffer()
        capacity += len
        currentSegment = currentSegment.next ?: break
    } while (idx < iovec.size)

    val bytesRead = readAction(iovec, idx)
    if (bytesRead != 0L) {
        if (bytesRead < 0 || bytesRead > capacity) {
            throw IllegalStateException(
                "readAction should return a value in range [0, $capacity], but returned: $bytesRead"
            )
        }
        buffer.skip(bytesRead)
    }
    return bytesRead
}
