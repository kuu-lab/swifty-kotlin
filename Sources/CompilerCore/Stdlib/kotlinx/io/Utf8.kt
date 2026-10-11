/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Copyright (C) 2017 Square, Inc.
 * Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
 * Derived from kotlinx-io core/common/src/Utf8.kt (tag 0.9.1).
 */
package kotlinx.io

import kotlinx.io.internal.*
import kotlinx.io.unsafe.UnsafeBufferOperations

internal fun String.utf8Size(startIndex: Int = 0, endIndex: Int = this.length): Long =
    this.commonUtf8Size(startIndex, endIndex)

@OptIn(DelicateIoApi::class)
public fun Sink.writeString(string: String, startIndex: Int = 0, endIndex: Int = string.length) {
    checkBounds(string.length, startIndex, endIndex)
    writeToInternalBuffer { it.commonWriteUtf8(startIndex, endIndex, string::get) }
}

@OptIn(DelicateIoApi::class)
public fun Sink.writeString(chars: CharSequence, startIndex: Int = 0, endIndex: Int = chars.length) {
    checkBounds(chars.length, startIndex, endIndex)
    writeToInternalBuffer { it.commonWriteUtf8(startIndex, endIndex, chars::get) }
}

@OptIn(DelicateIoApi::class)
public fun Sink.writeCodePointValue(codePoint: Int): Unit =
    writeToInternalBuffer { it.commonWriteUtf8CodePoint(codePoint) }

@OptIn(InternalIoApi::class)
public fun Source.readString(): String {
    this.request(Long.MAX_VALUE)
    return this.buffer.commonReadUtf8(this.buffer.size)
}

public fun Buffer.readString(): String = this.commonReadUtf8(this.size)

@OptIn(InternalIoApi::class)
public fun Source.readString(byteCount: Long): String {
    this.require(byteCount)
    return this.buffer.commonReadUtf8(byteCount)
}

private fun Buffer.commonReadUtf8(byteCount: Long): String {
    if (byteCount > Int.MAX_VALUE.toLong()) {
        throw IllegalArgumentException("byteCount ($byteCount) exceeds Int.MAX_VALUE")
    }
    val bytes = ByteArray(byteCount.toInt())
    var offset = 0
    while (offset < bytes.size) {
        offset += this.readAtMostTo(bytes, offset, bytes.size)
    }
    return bytes.commonToUtf8String()
}

@OptIn(InternalIoApi::class)
public fun Source.readCodePointValue(): Int {
    if (this is Buffer) return commonReadUtf8CodePoint()
    this.require(1)
    val b0 = this.buffer[0L].toInt()
    when {
        b0 and 0xe0 == 0xc0 -> this.require(2)
        b0 and 0xf0 == 0xe0 -> this.require(3)
        b0 and 0xf8 == 0xf0 -> this.require(4)
    }
    return this.buffer.commonReadUtf8CodePoint()
}

@OptIn(InternalIoApi::class)
public fun Source.readLine(): String? {
    if (!this.request(1)) return null
    var lfIndex = this.indexOf(10.toByte())
    if (lfIndex == -1L) return this.readString()
    var skipBytes = 1L
    if (lfIndex > 0L && this.buffer[lfIndex - 1L] == 13.toByte()) {
        lfIndex -= 1L
        skipBytes += 1L
    }
    val result = this.readString(lfIndex)
    this.skip(skipBytes)
    return result
}

@OptIn(InternalIoApi::class)
public fun Source.readLineStrict(limit: Long = Long.MAX_VALUE): String {
    if (limit < 0L) throw IllegalArgumentException("limit ($limit) < 0")
    this.require(1)
    var lfIndex = this.indexOf(10.toByte(), 0L, limit)
    if (lfIndex >= 0L) {
        var skipBytes = 1L
        if (lfIndex > 0L && this.buffer[lfIndex - 1L] == 13.toByte()) {
            lfIndex -= 1L
            skipBytes += 1L
        }
        val result = this.readString(lfIndex)
        this.skip(skipBytes)
        return result
    }
    if (this.buffer.size < limit || limit == Long.MAX_VALUE || !this.request(limit + 1L)) throw EOFException()
    val b = this.buffer[limit]
    if (b == 10.toByte()) {
        val result = this.readString(limit)
        this.skip(1)
        return result
    }
    if (b != 13.toByte() || !this.request(limit + 2L) || this.buffer[limit + 1L] != 10.toByte()) throw EOFException()
    val result = this.readString(limit)
    this.skip(2)
    return result
}

// Pinned 0.9.1 validation/streaming helpers. Unused writeToTail result bindings
// are omitted; all byte commits, continuation consumption and getter order remain.
private fun Buffer.commonReadUtf8CodePoint(): Int {
    require(1)

    val b0 = this[0]
    var codePoint: Int
    val byteCount: Int
    val min: Int

    when {
        b0 and 0x80 == 0 -> {
            // 0xxxxxxx.
            codePoint = b0 and 0x7f
            byteCount = 1 // 7 bits (ASCII).
            min = 0x0
        }

        b0 and 0xe0 == 0xc0 -> {
            // 0x110xxxxx
            codePoint = b0 and 0x1f
            byteCount = 2 // 11 bits (5 + 6).
            min = 0x80
        }

        b0 and 0xf0 == 0xe0 -> {
            // 0x1110xxxx
            codePoint = b0 and 0x0f
            byteCount = 3 // 16 bits (4 + 6 + 6).
            min = 0x800
        }

        b0 and 0xf8 == 0xf0 -> {
            // 0x11110xxx
            codePoint = b0 and 0x07
            byteCount = 4 // 21 bits (3 + 6 + 6 + 6).
            min = 0x10000
        }

        else -> {
            // We expected the first byte of a code point but got something else.
            skip(1)
            return REPLACEMENT_CODE_POINT
        }
    }

    if (size < byteCount) {
        throw EOFException("size < $byteCount: $size (to read code point prefixed 0x${b0.toHexString()})")
    }

    // Read the continuation bytes. If we encounter a non-continuation byte, the sequence consumed
    // thus far is truncated and is decoded as the replacement character. That non-continuation byte
    // is left in the stream for processing by the next call to readUtf8CodePoint().
    for (i in 1 until byteCount) {
        val b = this[i.toLong()]
        if (b and 0xc0 == 0x80) {
            // 0x10xxxxxx
            codePoint = codePoint shl 6
            codePoint = codePoint or (b and 0x3f)
        } else {
            skip(i.toLong())
            return REPLACEMENT_CODE_POINT
        }
    }

    skip(byteCount.toLong())

    return when {
        codePoint > 0x10ffff -> {
            REPLACEMENT_CODE_POINT // Reject code points larger than the Unicode maximum.
        }

        codePoint in 0xd800..0xdfff -> {
            REPLACEMENT_CODE_POINT // Reject partial surrogates.
        }

        codePoint < min -> {
            REPLACEMENT_CODE_POINT // Reject overlong code points.
        }

        else -> codePoint
    }
}

@OptIn(UnsafeIoApi::class)
private inline fun Buffer.commonWriteUtf8(beginIndex: Int, endIndex: Int, charAt: (Int) -> Char) {
    // Transcode a UTF-16 chars to UTF-8 bytes.
    var i = beginIndex
    while (i < endIndex) {
        var c = charAt(i).code

        when {
            c < 0x80 -> {
                UnsafeBufferOperations.writeToTail(this, 1) { ctx, segment ->
                    val segmentOffset = -i
                    val runLimit = minOf(endIndex, i + segment.remainingCapacity)

                    // Emit a 7-bit character with 1 byte.
                    ctx.setUnchecked(segment, segmentOffset + i++, c.toByte()) // 0xxxxxxx

                    // Fast-path contiguous runs of ASCII characters. This is ugly, but yields a ~4x performance
                    // improvement over independent calls to writeByte().
                    while (i < runLimit) {
                        c = charAt(i).code
                        if (c >= 0x80) break
                        ctx.setUnchecked(segment, segmentOffset + i++, c.toByte()) // 0xxxxxxx
                    }

                    i + segmentOffset // Equivalent to i - (previous i).
                }
            }

            c < 0x800 -> {
                // Emit a 11-bit character with 2 bytes.
                UnsafeBufferOperations.writeToTail(this, 2) { ctx, segment ->
                    ctx.setUnchecked(
                        segment, 0,
                        (c shr 6 or 0xc0).toByte(), // 110xxxxx
                        (c and 0x3f or 0x80).toByte() // 10xxxxxx
                    )
                    2
                }
                i++
            }

            c < 0xd800 || c > 0xdfff -> {
                // Emit a 16-bit character with 3 bytes.
                UnsafeBufferOperations.writeToTail(this, 3) { ctx, segment ->
                    ctx.setUnchecked(
                        segment, 0,
                        (c shr 12 or 0xe0).toByte(), // 1110xxxx
                        (c shr 6 and 0x3f or 0x80).toByte(), // 10xxxxxx
                        (c and 0x3f or 0x80).toByte() // 10xxxxxx
                    )
                    3
                }
                i++
            }

            else -> {
                // c is a surrogate. Make sure it is a high surrogate & that its successor is a low
                // surrogate. If not, the UTF-16 is invalid, in which case we emit a replacement
                // character.
                val low = (if (i + 1 < endIndex) charAt(i + 1).code else 0)
                if (c > 0xdbff || low !in 0xdc00..0xdfff) {
                    writeByte('?'.code.toByte())
                    i++
                } else {
                    // UTF-16 high surrogate: 110110xxxxxxxxxx (10 bits)
                    // UTF-16 low surrogate:  110111yyyyyyyyyy (10 bits)
                    // Unicode code point:    00010000000000000000 + xxxxxxxxxxyyyyyyyyyy (21 bits)
                    val codePoint = 0x010000 + (c and 0x03ff shl 10 or (low and 0x03ff))

                    // Emit a 21-bit character with 4 bytes.
                    UnsafeBufferOperations.writeToTail(this, 4) { ctx, segment ->
                        ctx.setUnchecked(segment, 0,
                            (codePoint shr 18 or 0xf0).toByte(), // 11110xxx
                            (codePoint shr 12 and 0x3f or 0x80).toByte(), // 10xxxxxx
                            (codePoint shr 6 and 0x3f or 0x80).toByte(), // 10xxyyyy
                            (codePoint and 0x3f or 0x80).toByte() // 10yyyyyy
                        )
                        4
                    }
                    i += 2
                }
            }
        }
    }
}

@OptIn(UnsafeIoApi::class)
private fun Buffer.commonWriteUtf8CodePoint(codePoint: Int) {
    when {
        codePoint < 0 || codePoint > 0x10ffff -> {
            throw IllegalArgumentException(
                "Code point value is out of Unicode codespace 0..0x10ffff: 0x${codePoint.toHexString()} ($codePoint)"
            )
        }

        codePoint < 0x80 -> {
            // Emit a 7-bit code point with 1 byte.
            writeByte(codePoint.toByte())
        }

        codePoint < 0x800 -> {
            // Emit a 11-bit code point with 2 bytes.
            UnsafeBufferOperations.writeToTail(this, 2) { ctx, segment ->
                ctx.setUnchecked(segment, 0, (codePoint shr 6 or 0xc0).toByte()) // 110xxxxx
                ctx.setUnchecked(segment, 1, (codePoint and 0x3f or 0x80).toByte()) // 10xxxxxx
                2
            }
        }

        codePoint in 0xd800..0xdfff -> {
            // Emit a replacement character for a partial surrogate.
            writeByte('?'.code.toByte())
        }

        codePoint < 0x10000 -> {
            // Emit a 16-bit code point with 3 bytes.
            UnsafeBufferOperations.writeToTail(this, 3) { ctx, segment ->
                ctx.setUnchecked(segment, 0, (codePoint shr 12 or 0xe0).toByte()) // 1110xxxx
                ctx.setUnchecked(segment, 1, (codePoint shr 6 and 0x3f or 0x80).toByte()) // 10xxxxxx
                ctx.setUnchecked(segment, 2, (codePoint and 0x3f or 0x80).toByte()) // 10xxxxxx
                3
            }
        }

        else -> { // [0x10000, 0x10ffff]
            // Emit a 21-bit code point with 4 bytes.
            UnsafeBufferOperations.writeToTail(this, 4) { ctx, segment ->
                ctx.setUnchecked(segment,0, (codePoint shr 18 or 0xf0).toByte()) // 11110xxx
                ctx.setUnchecked(segment,1, (codePoint shr 12 and 0x3f or 0x80).toByte()) // 10xxxxxx
                ctx.setUnchecked(segment,2, (codePoint shr 6 and 0x3f or 0x80).toByte()) // 10xxyyyy
                ctx.setUnchecked(segment,3, (codePoint and 0x3f or 0x80).toByte()) // 10yyyyyy
                4
            }
        }
    }
}
