/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE.txt file.
 *
 * Derived from kotlinx-io core/common/src/ByteStrings.kt (tag 0.9.1).
 * The readByteArray helpers from Sources.kt are not bundled yet, so reads copy from the buffer here.
 */
package kotlinx.io

import kotlinx.io.bytestring.ByteString
import kotlinx.io.bytestring.unsafe.UnsafeByteStringApi
import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations
import kotlinx.io.unsafe.UnsafeBufferOperations

/** Writes the subsequence [startIndex, endIndex) of [byteString] to this sink. */
@OptIn(DelicateIoApi::class, UnsafeByteStringApi::class, UnsafeIoApi::class)
public fun Sink.write(byteString: ByteString, startIndex: Int = 0, endIndex: Int = byteString.size) {
    checkBounds(byteString.size, startIndex, endIndex)
    if (startIndex == endIndex) return

    writeToInternalBuffer { buffer ->
        var offset = startIndex
        UnsafeByteStringOperations.withByteArrayUnsafe(byteString) { data ->
            while (offset < endIndex) {
                val written = UnsafeBufferOperations.writeToTail(buffer, 1) { segmentData, pos, limit ->
                    val count = minOf(endIndex - offset, limit - pos)
                    data.copyInto(segmentData, pos, offset, offset + count)
                    count
                }
                offset += written
            }
        }
    }
}

/** Consumes all bytes from this source and returns them as an immutable byte string. */
public fun Source.readByteString(): ByteString {
    var fetchSize = Int.MAX_VALUE.toLong()
    while (buffer.size < Int.MAX_VALUE && request(fetchSize)) {
        fetchSize *= 2L
    }
    check(buffer.size < Int.MAX_VALUE) { "Can't create an array of size ${buffer.size}" }
    return readByteString(buffer.size.toInt())
}

/** Consumes exactly [byteCount] bytes, throwing [EOFException] if there are not enough. */
@OptIn(UnsafeByteStringApi::class)
public fun Source.readByteString(byteCount: Int): ByteString {
    checkByteCount(byteCount.toLong())
    require(byteCount.toLong())
    val data = ByteArray(byteCount)
    var offset = 0
    while (offset < byteCount) {
        offset += buffer.readAtMostTo(data, offset, byteCount)
    }
    return UnsafeByteStringOperations.wrapUnsafe(data)
}

/** Searches without consuming bytes, fetching more data into the buffer as needed. */
public fun Source.indexOf(byteString: ByteString, startIndex: Long = 0L): Long {
    val start = maxOf(0L, startIndex)
    if (byteString.size == 0) {
        request(start)
        return minOf(start, buffer.size)
    }

    var offset = start
    while (request(offset + byteString.size)) {
        val index = buffer.indexOf(byteString, offset)
        if (index >= 0L) return index
        offset = buffer.size - byteString.size + 1L
    }
    return -1L
}

/** Returns the first match at or after [startIndex], or -1 if the pattern is absent. */
@OptIn(UnsafeByteStringApi::class)
public fun Buffer.indexOf(byteString: ByteString, startIndex: Long = 0L): Long {
    val start = maxOf(0L, minOf(startIndex, size))
    if (byteString.size == 0) return start
    if (start > size - byteString.size) return -1L

    var result = -1L
    UnsafeByteStringOperations.withByteArrayUnsafe(byteString) { bytes ->
        result = indexOfBytes(bytes, start)
    }
    return result
}

private fun Buffer.indexOfBytes(bytes: ByteArray, start: Long): Long {
    seek(start) { head, headOffset ->
        if (headOffset == -1L) return -1L
        var segment = head
        var offset = headOffset
        do {
            val current = segment!!
            val startOffset = maxOf((start - offset).toInt(), 0)
            val inbound = current.indexOfBytesInbound(bytes, startOffset)
            if (inbound != -1) return offset + inbound

            val outboundStart = maxOf(startOffset, current.size - bytes.size + 1)
            val outbound = current.indexOfBytesOutbound(bytes, outboundStart)
            if (outbound != -1) return offset + outbound

            offset += current.size
            segment = current.next
        } while (segment != null && offset + bytes.size <= size)
        return -1L
    }
    return -1L
}
