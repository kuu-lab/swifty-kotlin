/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Adapted from kotlinx-io 0.9.1 bytestring/common/src/ByteString.kt.
 */
package kotlinx.io.bytestring

/** An immutable sequence of bytes. Public construction and extraction copy the array. */
public class ByteString private constructor(private val data: ByteArray, unused: Boolean) : Comparable<ByteString> {
    public constructor(data: ByteArray, startIndex: Int = 0, endIndex: Int = data.size) :
        this(copyByteStringData(data, startIndex, endIndex), true)

    public companion object {
        internal val EMPTY: ByteString = ByteString(ByteArray(0), true)

        // Unsafe callers promise that no one will modify the backing array.
        internal fun wrap(data: ByteArray): ByteString = ByteString(data, true)
    }

    public val size: Int get() = data.size

    public operator fun get(index: Int): Byte {
        if (index < 0 || index >= size) {
            throw IndexOutOfBoundsException("index ($index) is out of byte string bounds: [0..$size)")
        }
        return data[index]
    }

    public fun toByteArray(startIndex: Int = 0, endIndex: Int = size): ByteArray {
        require(startIndex <= endIndex) { "startIndex ($startIndex) > endIndex ($endIndex)" }
        return data.copyOfRange(startIndex, endIndex)
    }

    public fun copyInto(
        destination: ByteArray, destinationOffset: Int = 0,
        startIndex: Int = 0, endIndex: Int = size
    ) {
        require(startIndex <= endIndex) { "startIndex ($startIndex) > endIndex ($endIndex)" }
        data.copyInto(destination, destinationOffset, startIndex, endIndex)
    }

    public fun substring(startIndex: Int, endIndex: Int = size): ByteString =
        if (startIndex == endIndex) EMPTY else ByteString(data, startIndex, endIndex)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ByteString) return false
        return data.contentEquals(other.data)
    }

    override fun hashCode(): Int = data.contentHashCode()

    override fun compareTo(other: ByteString): Int {
        val count = if (size < other.size) size else other.size
        var i = 0
        while (i < count) {
            val left = data[i].toInt() and 255
            val right = other.data[i].toInt() and 255
            if (left != right) return if (left < right) -1 else 1
            i++
        }
        return size.compareTo(other.size)
    }

    override fun toString(): String {
        if (size == 0) return "ByteString(size=0)"
        val digits = "0123456789abcdef"
        val result = StringBuilder(size * 2 + 32)
        result.append("ByteString(size=")
        result.append(size)
        result.append(" hex=")
        var i = 0
        while (i < size) {
            val value = data[i].toInt() and 255
            result.append(digits[(value ushr 4) and 15])
            result.append(digits[value and 15])
            i++
        }
        result.append(')')
        return result.toString()
    }

    @PublishedApi
    internal fun getBackingArrayReference(): ByteArray = data
}

private fun copyByteStringData(data: ByteArray, startIndex: Int, endIndex: Int): ByteArray {
    // Kotlin copyOfRange checks an excessive end before a reversed range,
    // and checks a negative start after the reversed-range check.
    if (endIndex > data.size) {
        throw IndexOutOfBoundsException("endIndex ($endIndex) exceeds size (${data.size})")
    }
    if (startIndex > endIndex) {
        throw IllegalArgumentException("startIndex ($startIndex) > endIndex ($endIndex)")
    }
    if (startIndex < 0) {
        throw IndexOutOfBoundsException("startIndex ($startIndex) is negative")
    }
    return data.copyOfRange(startIndex, endIndex)
}

@kotlin.js.JsName("EmptyByteString")
public fun ByteString(): ByteString = ByteString.EMPTY

public fun ByteString(vararg bytes: Byte): ByteString {
    if (bytes.isEmpty()) return ByteString.EMPTY
    val array = ByteArray(bytes.size)
    var i = 0
    for (byte in bytes) {
        array[i] = byte
        i++
    }
    return ByteString.wrap(array)
}

@OptIn(ExperimentalUnsignedTypes::class)
public fun ByteString(vararg bytes: UByte): ByteString {
    if (bytes.isEmpty()) return ByteString.EMPTY
    val array = ByteArray(bytes.size)
    var i = 0
    for (byte in bytes) {
        array[i] = byte.toByte()
        i++
    }
    return ByteString.wrap(array)
}

public val ByteString.indices: IntRange get() = 0 until size
public fun ByteString.isEmpty(): Boolean = size == 0
public fun ByteString.isNotEmpty(): Boolean = size != 0

private fun ByteString.rangeEquals(offset: Int, other: ByteArray): Boolean {
    var i = 0
    while (i < other.size) {
        if (this[offset + i] != other[i]) return false
        i++
    }
    return true
}

public fun ByteString.indexOf(byte: Byte, startIndex: Int = 0): Int {
    var i = if (startIndex < 0) 0 else startIndex
    while (i < size) {
        if (this[i] == byte) return i
        i++
    }
    return -1
}

public fun ByteString.indexOf(byteString: ByteString, startIndex: Int = 0): Int =
    indexOf(byteString.getBackingArrayReference(), startIndex)

public fun ByteString.indexOf(byteArray: ByteArray, startIndex: Int = 0): Int {
    val start = if (startIndex < 0) 0 else startIndex
    if (byteArray.isEmpty()) return if (start > size) size else start
    var i = start
    while (i <= size - byteArray.size) {
        if (rangeEquals(i, byteArray)) return i
        i++
    }
    return -1
}

public fun ByteString.lastIndexOf(byte: Byte, startIndex: Int = 0): Int {
    var i = size - 1
    val lower = if (startIndex < 0) 0 else startIndex
    while (i >= lower) {
        if (this[i] == byte) return i
        i--
    }
    return -1
}

public fun ByteString.lastIndexOf(byteString: ByteString, startIndex: Int = 0): Int =
    lastIndexOf(byteString.getBackingArrayReference(), startIndex)

public fun ByteString.lastIndexOf(byteArray: ByteArray, startIndex: Int = 0): Int {
    if (byteArray.isEmpty()) return size
    var i = size - byteArray.size
    val lower = if (startIndex < 0) 0 else startIndex
    while (i >= lower) {
        if (rangeEquals(i, byteArray)) return i
        i--
    }
    return -1
}

public fun ByteString.startsWith(byteArray: ByteArray): Boolean =
    byteArray.size <= size && rangeEquals(0, byteArray)
public fun ByteString.startsWith(byteString: ByteString): Boolean =
    startsWith(byteString.getBackingArrayReference())
public fun ByteString.endsWith(byteArray: ByteArray): Boolean =
    byteArray.size <= size && rangeEquals(size - byteArray.size, byteArray)
public fun ByteString.endsWith(byteString: ByteString): Boolean =
    endsWith(byteString.getBackingArrayReference())

public fun ByteString.decodeToString(): String = getBackingArrayReference().decodeToString()
// `this.` is load-bearing: an unqualified call would resolve through
// package-scope candidates, where the same-named (inapplicable)
// `kotlinx.io.bytestring.Base64.encodeToByteArray` extension suppresses the
// kotlin.text `String.encodeToByteArray` fallback.
public fun String.encodeToByteString(): ByteString = ByteString.wrap(this.encodeToByteArray())
public fun ByteString.contentEquals(array: ByteArray): Boolean =
    getBackingArrayReference().contentEquals(array)
