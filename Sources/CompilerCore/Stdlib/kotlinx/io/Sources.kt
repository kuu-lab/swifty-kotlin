/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE.txt file.
 *
 * Derived from kotlinx-io core/common/src/Sources.kt (tag 0.9.1).
 * Explicit get(Long) avoids the compiler's Buffer subscript fallback.
 */
package kotlinx.io

public fun Source.readShortLe(): Short = this.readShort().reverseBytes()
public fun Source.readIntLe(): Int = this.readInt().reverseBytes()
public fun Source.readLongLe(): Long = this.readLong().reverseBytes()

internal const val OVERFLOW_ZONE: Long = -922337203685477580L
internal const val OVERFLOW_DIGIT_START: Long = -7L

@OptIn(InternalIoApi::class)
public fun Source.readDecimalLong(): Long {
    this.require(1L)
    var negative = false
    var value = 0L
    var overflowDigit = OVERFLOW_DIGIT_START
    val first = this.buffer.get(0L)
    if (first == '-'.code.toByte()) {
        negative = true
        overflowDigit -= 1L
        this.require(2L)
        val digit = this.buffer.get(1L).toInt()
        if (digit < '0'.code || digit > '9'.code) {
            throw NumberFormatException("Expected a digit but was 0x${this.buffer.get(1L).toHexString()}")
        }
    } else if (first.toInt() >= '0'.code && first.toInt() <= '9'.code) {
        value = ('0'.code - first.toInt()).toLong()
    } else {
        throw NumberFormatException("Expected a digit or '-' but was 0x${first.toHexString()}")
    }

    var offset = 1L
    while (this.request(offset + 1L)) {
        val byte = this.buffer.get(offset)
        if (byte.toInt() < '0'.code || byte.toInt() > '9'.code) break
        val digit = ('0'.code - byte.toInt()).toLong()
        if (value < OVERFLOW_ZONE || (value == OVERFLOW_ZONE && digit < overflowDigit)) {
            val prefix = if (negative) value.toString() else value.toString().substring(1)
            throw NumberFormatException("Number too large: $prefix${byte.toInt().toChar()}")
        }
        value = value * 10L + digit
        offset += 1L
    }
    this.skip(offset)
    return if (negative) value else -value
}

private fun hexadecimalDigit(byte: Byte): Int {
    val value = byte.toInt()
    if (value >= '0'.code && value <= '9'.code) return value - '0'.code
    if (value >= 'a'.code && value <= 'f'.code) return value - 'a'.code + 10
    if (value >= 'A'.code && value <= 'F'.code) return value - 'A'.code + 10
    return -1
}

@OptIn(InternalIoApi::class)
public fun Source.readHexadecimalUnsignedLong(): Long {
    this.require(1L)
    val first = this.buffer.get(0L)
    var result = hexadecimalDigit(first).toLong()
    if (result < 0L) {
        throw NumberFormatException("Expected leading [0-9a-fA-F] character but was 0x${first.toHexString()}")
    }
    var offset = 1L
    while (this.request(offset + 1L)) {
        val byte = this.buffer.get(offset)
        val digit = hexadecimalDigit(byte)
        if (digit < 0) break
        if ((result and -0x1000000000000000L) != 0L) {
            throw NumberFormatException("Number too large: ${result.toHexString()}${byte.toInt().toChar()}")
        }
        result = (result shl 4) + digit.toLong()
        offset += 1L
    }
    this.skip(offset)
    return result
}

/**
 * Returns an index of [byte] first occurrence in the range of [startIndex] to [endIndex],
 * or `-1` when the range doesn't contain [byte].
 *
 * The scan terminates at either [endIndex] or source's exhaustion, whichever comes first. The
 * maximum number of bytes scanned is `toIndex-fromIndex`.
 * If [byte] not found in buffered data, [endIndex] is yet to be reached and the underlying source is not yet exhausted
 * then new data will be read from the underlying source into the buffer.
 *
 * @param byte the value to find.
 * @param startIndex the start of the range (inclusive) to find [byte], `0` by default.
 * @param endIndex the end of the range (exclusive) to find [byte], [Long.MAX_VALUE] by default.
 *
 * @throws IllegalStateException when the source is closed.
 * @throws IllegalArgumentException when `startIndex > endIndex` or either of indices is negative.
 * @throws IOException when some I/O error occurs.
 *
 * @sample kotlinx.io.samples.KotlinxIoCoreCommonSamples.indexOfByteSample
 */
@OptIn(InternalIoApi::class)
public fun Source.indexOf(byte: Byte, startIndex: Long = 0L, endIndex: Long = Long.MAX_VALUE): Long {
    if (startIndex < 0L || startIndex > endIndex) {
        val message = if (endIndex < 0L) {
            "startIndex ($startIndex) and endIndex ($endIndex) should be non negative"
        } else {
            "startIndex ($startIndex) is not within the range [0..endIndex($endIndex))"
        }
        throw IllegalArgumentException(message)
    }
    var offset = startIndex
    while (offset < endIndex && this.request(offset + 1L)) {
        val limit = if (endIndex < this.buffer.size) endIndex else this.buffer.size
        val index = this.buffer.indexOf(byte, offset, limit)
        if (index != -1L) return index
        offset = this.buffer.size
    }
    return -1L
}

public fun Source.readByteArray(): ByteArray = this.readByteArrayImpl(-1)

public fun Source.readByteArray(byteCount: Int): ByteArray {
    checkByteCount(byteCount.toLong())
    return this.readByteArrayImpl(byteCount)
}

@OptIn(InternalIoApi::class)
private fun Source.readByteArrayImpl(size: Int): ByteArray {
    var arraySize = size
    if (size == -1) {
        var fetchSize = Int.MAX_VALUE.toLong()
        while (this.buffer.size < Int.MAX_VALUE.toLong() && this.request(fetchSize)) {
            fetchSize *= 2L
        }
        check(this.buffer.size < Int.MAX_VALUE.toLong()) { "Can't create an array of size ${this.buffer.size}" }
        arraySize = this.buffer.size.toInt()
    } else {
        this.require(size.toLong())
    }
    val array = ByteArray(arraySize)
    this.buffer.readTo(array)
    return array
}

public fun Source.readTo(sink: ByteArray, startIndex: Int = 0, endIndex: Int = sink.size) {
    checkBounds(sink.size, startIndex, endIndex)
    var offset = startIndex
    while (offset < endIndex) {
        val bytesRead = this.readAtMostTo(sink, offset, endIndex)
        if (bytesRead == -1) {
            throw EOFException(
                "Source exhausted before reading ${endIndex - startIndex} bytes. Only $bytesRead bytes were read."
            )
        }
        offset += bytesRead
    }
}

public fun Source.readAtMostTo(
    sink: ByteArray,
    startIndex: Int = 0,
    endIndex: Int = sink.size
): Int = this.readAtMostTo(sink, startIndex, endIndex)

public fun Source.readUByte(): UByte = this.readByte().toUByte()
public fun Source.readUShort(): UShort = this.readShort().toInt().toUShort()
public fun Source.readUInt(): UInt = this.readInt().toUInt()
public fun Source.readULong(): ULong = this.readLong().toULong()
public fun Source.readUShortLe(): UShort = this.readShortLe().toInt().toUShort()
public fun Source.readUIntLe(): UInt = this.readIntLe().toUInt()
public fun Source.readULongLe(): ULong = this.readLongLe().toULong()
public fun Source.readFloat(): Float = Float.fromBits(this.readInt())
public fun Source.readDouble(): Double = Double.fromBits(this.readLong())
public fun Source.readFloatLe(): Float = Float.fromBits(this.readIntLe())
public fun Source.readDoubleLe(): Double = Double.fromBits(this.readLongLe())
@OptIn(InternalIoApi::class)
public fun Source.startsWith(byte: Byte): Boolean = this.request(1L) && this.buffer.get(0L) == byte
