/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Copyright (C) 2017 Square, Inc.
 * Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
 * Derived from kotlinx-io core/common/src/Utf8.kt (tag 0.9.1).
 */
package kotlinx.io

import kotlinx.io.internal.*

internal fun String.utf8Size(startIndex: Int = 0, endIndex: Int = this.length): Long =
    this.commonUtf8Size(startIndex, endIndex)

public fun Sink.writeString(string: String, startIndex: Int = 0, endIndex: Int = string.length) {
    val bytes = string.commonAsUtf8ToByteArray(startIndex, endIndex)
    this.write(bytes, 0, bytes.size)
}

public fun Sink.writeString(chars: CharSequence, startIndex: Int = 0, endIndex: Int = chars.length) {
    val bytes = encodeUtf8(chars, startIndex, endIndex)
    this.write(bytes, 0, bytes.size)
}

public fun Sink.writeCodePointValue(codePoint: Int) {
    if (codePoint < 0 || codePoint > 0x10ffff) {
        throw IllegalArgumentException(
            "Code point value is out of Unicode codespace 0..0x10ffff: 0x${codePoint.toHexString()} ($codePoint)"
        )
    }
    val chars = if (codePoint < 0x10000) CharArray(1) else CharArray(2)
    if (codePoint < 0x10000) {
        chars[0] = codePoint.toChar()
    } else {
        chars[0] = ((codePoint ushr 10) + HIGH_SURROGATE_HEADER).toChar()
        chars[1] = ((codePoint and 0x03ff) + LOG_SURROGATE_HEADER).toChar()
    }
    this.writeString(chars.concatToString())
}

public fun Source.readString(): String {
    this.request(Long.MAX_VALUE)
    return this.buffer.commonReadUtf8(this.buffer.size)
}

public fun Buffer.readString(): String = this.commonReadUtf8(this.size)

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

public fun Source.readCodePointValue(): Int {
    this.require(1)
    val b0 = this.buffer[0L].toInt()
    val byteCount = when {
        b0 and 0x80 == 0 -> 1
        b0 and 0xe0 == 0xc0 -> 2
        b0 and 0xf0 == 0xe0 -> 3
        b0 and 0xf8 == 0xf0 -> 4
        else -> {
            this.skip(1)
            return REPLACEMENT_CODE_POINT
        }
    }
    this.require(byteCount.toLong())
    var codePoint = b0 and (0x7f shr byteCount)
    if (byteCount == 1) codePoint = b0
    var i = 1
    while (i < byteCount) {
        val b = this.buffer[i.toLong()]
        if (!isUtf8Continuation(b)) {
            this.skip(i.toLong())
            return REPLACEMENT_CODE_POINT
        }
        codePoint = (codePoint shl 6) or (b.toInt() and 0x3f)
        i += 1
    }
    this.skip(byteCount.toLong())
    val min = when (byteCount) {
        2 -> 0x80
        3 -> 0x800
        4 -> 0x10000
        else -> 0
    }
    return if (codePoint < min || codePoint > 0x10ffff || (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
        REPLACEMENT_CODE_POINT
    } else {
        codePoint
    }
}

public fun Source.indexOf(byte: Byte, startIndex: Long = 0L, endIndex: Long = Long.MAX_VALUE): Long {
    if (startIndex < 0L || startIndex > endIndex) {
        throw IllegalArgumentException("startIndex ($startIndex) is not within the range [0..endIndex($endIndex))")
    }
    var offset = startIndex
    while (offset < endIndex && this.request(offset + 1L)) {
        val end = if (endIndex < this.buffer.size) endIndex else this.buffer.size
        val index = this.buffer.indexOf(byte, offset, end)
        if (index != -1L) return index
        offset = this.buffer.size
    }
    return -1L
}

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
