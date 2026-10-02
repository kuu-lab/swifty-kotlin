/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 * Copyright (C) 2018 Square, Inc. Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-io core/common/src/-Util.kt (tag 0.9.1). The three expect reverseBytes
 * functions use upstream's portable Common implementations for this single-target compiler.
 */
package kotlinx.io

// Stored top-level val initializers deserialize as null from .kklib stdlib
// artifacts in this compiler, so constants are exposed as `const` strings.
internal const val HEX_DIGIT_CHARS = "0123456789abcdef"

internal fun checkOffsetAndCount(size: Long, offset: Long, byteCount: Long) {
    if (offset < 0L || offset > size || size - offset < byteCount || byteCount < 0L) {
        throw IllegalArgumentException(
            "offset ($offset) and byteCount ($byteCount) are not within the range [0..size($size))"
        )
    }
}

internal fun checkBounds(size: Int, startIndex: Int, endIndex: Int) {
    checkBounds(size.toLong(), startIndex.toLong(), endIndex.toLong())
}

internal fun checkBounds(size: Long, startIndex: Long, endIndex: Long) {
    if (startIndex < 0L || endIndex > size) {
        throw IndexOutOfBoundsException(
            "startIndex ($startIndex) and endIndex ($endIndex) are not within the range [0..size($size))"
        )
    }
    if (startIndex > endIndex) {
        throw IllegalArgumentException("startIndex ($startIndex) > endIndex ($endIndex)")
    }
}

internal fun checkByteCount(byteCount: Long) {
    if (byteCount < 0L) {
        throw IllegalArgumentException("byteCount ($byteCount) < 0")
    }
}

internal fun Short.reverseBytes(): Short {
    val i = toInt() and 0xffff
    return ((i and 0xff00 ushr 8) or (i and 0x00ff shl 8)).toShort()
}

internal fun Int.reverseBytes(): Int =
    (this and -0x1000000 ushr 24) or
        (this and 0x00ff0000 ushr 8) or
        (this and 0x0000ff00 shl 8) or
        (this and 0x000000ff shl 24)

internal fun Long.reverseBytes(): Long =
    (this and -0x100000000000000L ushr 56) or
        (this and 0x00ff000000000000L ushr 40) or
        (this and 0x0000ff0000000000L ushr 24) or
        (this and 0x000000ff00000000L ushr 8) or
        (this and 0x00000000ff000000L shl 8) or
        (this and 0x0000000000ff0000L shl 24) or
        (this and 0x000000000000ff00L shl 40) or
        (this and 0x00000000000000ffL shl 56)

internal infix fun Byte.shr(other: Int): Int = this.toInt() shr other
internal infix fun Byte.shl(other: Int): Int = this.toInt() shl other
internal infix fun Byte.and(other: Int): Int = this.toInt() and other
internal infix fun Byte.and(other: Long): Long = this.toLong() and other
internal infix fun Byte.xor(other: Byte): Byte = (this.toInt() xor other.toInt()).toByte()
internal infix fun Int.and(other: Long): Long = this.toLong() and other
// These mixed-sign helpers shadow kotlin.comparisons.minOf(Long, Long) inside
// this package, so compare directly instead of recursing into minOf.
internal fun minOf(a: Long, b: Int): Long = if (a <= b.toLong()) a else b.toLong()
internal fun minOf(a: Int, b: Long): Long = if (a.toLong() <= b) a.toLong() else b

internal fun Byte.toHexString(): String {
    val result = StringBuilder()
    result.append(HEX_DIGIT_CHARS[this.toInt() shr 4 and 0xf])
    result.append(HEX_DIGIT_CHARS[this.toInt() and 0xf])
    return result.toString()
}

internal fun Int.toHexString(): String {
    if (this == 0) return "0"
    val result = CharArray(8)
    var shift = 28
    var index = 0
    while (index < result.size) {
        result[index] = HEX_DIGIT_CHARS[(this shr shift) and 0xf]
        shift -= 4
        index += 1
    }
    var first = 0
    while (first < result.size && result[first] == '0') first += 1
    // The ranged CharArray.concatToString overload is being added independently
    // (KUU-931); keep this foundation usable on its own.
    val text = StringBuilder()
    while (first < result.size) {
        text.append(result[first])
        first += 1
    }
    return text.toString()
}

internal fun Long.toHexString(): String {
    if (this == 0L) return "0"
    val result = CharArray(16)
    var shift = 60
    var index = 0
    while (index < result.size) {
        result[index] = HEX_DIGIT_CHARS[((this shr shift) and 0xfL).toInt()]
        shift -= 4
        index += 1
    }
    var first = 0
    while (first < result.size && result[first] == '0') first += 1
    val text = StringBuilder()
    while (first < result.size) {
        text.append(result[first])
        first += 1
    }
    return text.toString()
}

internal fun hexNumberLength(v: Long): Int {
    if (v == 0L) return 1
    val exactWidth = Long.SIZE_BITS - v.countLeadingZeroBits()
    return (exactWidth + 3) / 4
}
