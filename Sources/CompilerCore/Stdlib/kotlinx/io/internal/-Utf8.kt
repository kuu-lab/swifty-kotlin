/*
 * Copyright 2017-2023 JetBrains s.r.o. and respective authors and developers.
 * Copyright (C) 2018 Square, Inc.
 * Licensed under the Apache License, Version 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
 * Derived from kotlinx-io core/common/src/internal/-Utf8.kt (tag 0.9.1).
 */
package kotlinx.io.internal

import kotlinx.io.checkBounds

internal const val REPLACEMENT_BYTE: Byte = 63
internal const val REPLACEMENT_CHARACTER: Char = '\ufffd'
internal const val REPLACEMENT_CODE_POINT: Int = 0xfffd
internal const val HIGH_SURROGATE_HEADER: Int = 0xd7c0
internal const val LOG_SURROGATE_HEADER: Int = 0xdc00
internal const val MASK_2BYTES: Int = 0x0f80
internal const val MASK_3BYTES: Int = -0x01e080
internal const val MASK_4BYTES: Int = 0x381f80

internal fun isIsoControl(codePoint: Int): Boolean =
    (codePoint >= 0 && codePoint <= 0x1f) || (codePoint >= 0x7f && codePoint <= 0x9f)

internal fun isUtf8Continuation(byte: Byte): Boolean = byte.toInt() and 0xc0 == 0x80

internal fun ByteArray.commonToUtf8String(beginIndex: Int = 0, endIndex: Int = this.size): String {
    if (beginIndex < 0 || endIndex > this.size || beginIndex > endIndex) {
        throw IndexOutOfBoundsException("size=${this.size} beginIndex=$beginIndex endIndex=$endIndex")
    }
    val chars = CharArray(endIndex - beginIndex)
    var length = 0
    this.processUtf16Chars(beginIndex, endIndex) { c ->
        chars[length] = c
        length += 1
    }
    return chars.concatToString(0, length)
}

internal fun ByteArray.processUtf8CodePoints(beginIndex: Int, endIndex: Int, yield: (Int) -> Unit) {
    var index = beginIndex
    while (index < endIndex) {
        val b0 = this[index].toInt()
        when {
            b0 >= 0 -> {
                yield(b0)
                index += 1
                while (index < endIndex && this[index] >= 0) {
                    yield(this[index].toInt())
                    index += 1
                }
            }
            b0 shr 5 == -2 -> index += this.process2Utf8Bytes(index, endIndex, yield)
            b0 shr 4 == -2 -> index += this.process3Utf8Bytes(index, endIndex, yield)
            b0 shr 3 == -2 -> index += this.process4Utf8Bytes(index, endIndex, yield)
            else -> {
                yield(REPLACEMENT_CODE_POINT)
                index += 1
            }
        }
    }
}

internal fun ByteArray.processUtf16Chars(beginIndex: Int, endIndex: Int, yield: (Char) -> Unit) {
    this.processUtf8CodePoints(beginIndex, endIndex) { codePoint ->
        if (codePoint < 0x10000) {
            yield(codePoint.toChar())
        } else {
            yield(((codePoint ushr 10) + HIGH_SURROGATE_HEADER).toChar())
            yield(((codePoint and 0x03ff) + LOG_SURROGATE_HEADER).toChar())
        }
    }
}

internal fun ByteArray.process2Utf8Bytes(beginIndex: Int, endIndex: Int, yield: (Int) -> Unit): Int {
    if (endIndex <= beginIndex + 1 || !isUtf8Continuation(this[beginIndex + 1])) {
        yield(REPLACEMENT_CODE_POINT)
        return 1
    }
    val codePoint = MASK_2BYTES xor this[beginIndex + 1].toInt() xor (this[beginIndex].toInt() shl 6)
    yield(if (codePoint < 0x80) REPLACEMENT_CODE_POINT else codePoint)
    return 2
}

internal fun ByteArray.process3Utf8Bytes(beginIndex: Int, endIndex: Int, yield: (Int) -> Unit): Int {
    if (endIndex <= beginIndex + 1 || !isUtf8Continuation(this[beginIndex + 1])) {
        yield(REPLACEMENT_CODE_POINT)
        return 1
    }
    if (endIndex <= beginIndex + 2 || !isUtf8Continuation(this[beginIndex + 2])) {
        yield(REPLACEMENT_CODE_POINT)
        return 2
    }
    val codePoint = MASK_3BYTES xor this[beginIndex + 2].toInt() xor
        (this[beginIndex + 1].toInt() shl 6) xor (this[beginIndex].toInt() shl 12)
    yield(if (codePoint < 0x800 || (codePoint >= 0xd800 && codePoint <= 0xdfff)) REPLACEMENT_CODE_POINT else codePoint)
    return 3
}

internal fun ByteArray.process4Utf8Bytes(beginIndex: Int, endIndex: Int, yield: (Int) -> Unit): Int {
    if (endIndex <= beginIndex + 1 || !isUtf8Continuation(this[beginIndex + 1])) {
        yield(REPLACEMENT_CODE_POINT)
        return 1
    }
    if (endIndex <= beginIndex + 2 || !isUtf8Continuation(this[beginIndex + 2])) {
        yield(REPLACEMENT_CODE_POINT)
        return 2
    }
    if (endIndex <= beginIndex + 3 || !isUtf8Continuation(this[beginIndex + 3])) {
        yield(REPLACEMENT_CODE_POINT)
        return 3
    }
    val codePoint = MASK_4BYTES xor this[beginIndex + 3].toInt() xor
        (this[beginIndex + 2].toInt() shl 6) xor (this[beginIndex + 1].toInt() shl 12) xor
        (this[beginIndex].toInt() shl 18)
    yield(if (codePoint < 0x10000 || codePoint > 0x10ffff) REPLACEMENT_CODE_POINT else codePoint)
    return 4
}

internal fun CharSequence.commonUtf8Size(beginIndex: Int = 0, endIndex: Int = this.length): Long {
    checkBounds(this.length, beginIndex, endIndex)
    var result = 0L
    var i = beginIndex
    while (i < endIndex) {
        val c = this[i].code
        when {
            c < 0x80 -> result += 1L
            c < 0x800 -> result += 2L
            c < 0xd800 || c > 0xdfff -> result += 3L
            else -> {
                val low = if (i + 1 < endIndex) this[i + 1].code else 0
                if (c <= 0xdbff && low >= 0xdc00 && low <= 0xdfff) {
                    result += 4L
                    i += 1
                } else {
                    result += 1L
                }
            }
        }
        i += 1
    }
    return result
}

internal fun String.commonAsUtf8ToByteArray(beginIndex: Int = 0, endIndex: Int = this.length): ByteArray =
    encodeUtf8(this, beginIndex, endIndex)

internal fun encodeUtf8(chars: CharSequence, beginIndex: Int, endIndex: Int): ByteArray {
    val size = chars.commonUtf8Size(beginIndex, endIndex)
    if (size > Int.MAX_VALUE.toLong()) throw IllegalArgumentException("UTF-8 size ($size) exceeds Int.MAX_VALUE")
    val bytes = ByteArray(size.toInt())
    var offset = 0
    var i = beginIndex
    while (i < endIndex) {
        val c = chars[i].code
        when {
            c < 0x80 -> {
                bytes[offset] = c.toByte()
                offset += 1
            }
            c < 0x800 -> {
                bytes[offset] = (c shr 6 or 0xc0).toByte()
                bytes[offset + 1] = (c and 0x3f or 0x80).toByte()
                offset += 2
            }
            c < 0xd800 || c > 0xdfff -> {
                bytes[offset] = (c shr 12 or 0xe0).toByte()
                bytes[offset + 1] = (c shr 6 and 0x3f or 0x80).toByte()
                bytes[offset + 2] = (c and 0x3f or 0x80).toByte()
                offset += 3
            }
            else -> {
                val low = if (i + 1 < endIndex) chars[i + 1].code else 0
                if (c > 0xdbff || low < 0xdc00 || low > 0xdfff) {
                    bytes[offset] = REPLACEMENT_BYTE
                    offset += 1
                } else {
                    val codePoint = 0x10000 + ((c and 0x03ff) shl 10) + (low and 0x03ff)
                    bytes[offset] = (codePoint shr 18 or 0xf0).toByte()
                    bytes[offset + 1] = (codePoint shr 12 and 0x3f or 0x80).toByte()
                    bytes[offset + 2] = (codePoint shr 6 and 0x3f or 0x80).toByte()
                    bytes[offset + 3] = (codePoint and 0x3f or 0x80).toByte()
                    offset += 4
                    i += 1
                }
            }
        }
        i += 1
    }
    return bytes
}
