/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE.txt file.
 *
 * Derived from kotlinx-io core/common/src/Sinks.kt (tag 0.9.1), simplified for this compiler:
 * - upstream formats decimal/hex digits straight into the sink's tail `Segment` via
 *   `kotlinx.io.unsafe.UnsafeBufferOperations`; this port has no `Segment` (see the note in
 *   Buffer.kt), so digits are staged in a `ByteArray` and written through
 *   `Sink.write(ByteArray, Int, Int)`. Observable behavior (bytes written, thrown exceptions)
 *   is identical.
 * - upstream's `-Util.kt` helpers (`reverseBytes`, `hexNumberLength`) are private functions
 *   here using the same `*Common` bodies.
 * - `writeDecimalLong`'s `Long.MIN_VALUE` shortcut calls `Sink.writeString` upstream; the
 *   UTF-8 codec (`Utf8.kt`) is not bundled yet, so the same ASCII bytes are written directly.
 * - `writeToInternalBuffer` keeps `inline` + `contract`, but the upstream opt-in annotations
 *   (`@DelicateIoApi`, `@OptIn(InternalIoApi::class, UnsafeIoApi::class)`) are dropped —
 *   `Annotations.kt` is not bundled yet.
 * - upstream's top-level `HEX_DIGIT_BYTES` array became a private function: stored top-level
 *   `val` initializers do not survive .kklib deserialization yet.
 * - `Sink.write(ByteArray)` / `Sink.write(ByteArray, Int)` are separate `Sink` members
 *   (upstream folds them into `write(ByteArray, Int, Int)`'s default parameter values —
 *   see the note in Sink.kt): an extension named `write` would be shadowed by the `write`
 *   members on `Buffer`/`RealSink`, and interface-method bodies are not lowered correctly.
 */
package kotlinx.io

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind
import kotlin.contracts.contract

// Upstream: `private val HEX_DIGIT_BYTES = ByteArray(16) { ... }`.
private fun hexDigitByte(digit: Int): Byte =
    ((if (digit < 10) '0'.code else 'a'.code - 10) + digit).toByte()

// Upstream `-Util.kt` declares these as `internal expect`/`internal inline` helpers.
private fun Short.reverseBytes(): Short {
    val i = this.toInt() and 0xffff
    val reversed = (i and 0xff00 ushr 8) or
            (i and 0x00ff shl 8)
    return reversed.toShort()
}

private fun Int.reverseBytes(): Int {
    return (this and -0x1000000 ushr 24) or
            (this and 0x00ff0000 ushr 8) or
            (this and 0x0000ff00 shl 8) or
            (this and 0x000000ff shl 24)
}

private fun Long.reverseBytes(): Long {
    return (this and -0x100000000000000L ushr 56) or
            (this and 0x00ff000000000000L ushr 40) or
            (this and 0x0000ff0000000000L ushr 24) or
            (this and 0x000000ff00000000L ushr 8) or
            (this and 0x00000000ff000000L shl 8) or
            (this and 0x0000000000ff0000L shl 24) or
            (this and 0x000000000000ff00L shl 40) or
            (this and 0x00000000000000ffL shl 56)
}

/**
 * Returns the number of characters required to encode [v]
 * as a hexadecimal number without leading zeros (with `v == 0L` being the only exception,
 * `hexNumberLength(0) == 1`).
 */
private fun hexNumberLength(v: Long): Int {
    if (v == 0L) return 1
    val exactWidth = (Long.SIZE_BITS - v.countLeadingZeroBits())
    // Round up to the nearest full nibble
    return ((exactWidth + 3) / 4)
}

/**
 * Writes two bytes containing [short], in the little-endian order, to this sink.
 *
 * @param short the short integer to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeShortLe(short: Short) {
    this.writeShort(short.reverseBytes())
}

/**
 * Writes four bytes containing [int], in the little-endian order, to this sink.
 *
 * @param int the integer to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeIntLe(int: Int) {
    this.writeInt(int.reverseBytes())
}

/**
 * Writes eight bytes containing [long], in the little-endian order, to this sink.
 *
 * @param long the long integer to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeLongLe(long: Long) {
    this.writeLong(long.reverseBytes())
}

/**
 * Writes [long] to this sink in signed decimal form (i.e., as a string in base 10).
 *
 * Resulting string will not contain leading zeros, except the `0` value itself.
 *
 * @param long the long to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeDecimalLong(long: Long) {
    var v = long
    if (v == 0L) {
        // Both a shortcut and required since the following code can't handle zero.
        this.writeByte('0'.code.toByte())
        return
    }

    var negative = false
    if (v < 0L) {
        v = -v
        if (v < 0L) { // Only true for Long.MIN_VALUE.
            // Upstream calls writeString("-9223372036854775808"); the UTF-8 codec is not
            // bundled yet, but these digits are plain ASCII, so write them directly.
            val minValue = "-9223372036854775808"
            var i = 0
            while (i < minValue.length) {
                this.writeByte(minValue[i].code.toByte())
                i += 1
            }
            return
        }
        negative = true
    }

    // Binary search for character width which favors matching lower numbers.
    var width =
        if (v < 100000000L)
            if (v < 10000L)
                if (v < 100L)
                    if (v < 10L) 1
                    else 2
                else if (v < 1000L) 3
                else 4
            else if (v < 1000000L)
                if (v < 100000L) 5
                else 6
            else if (v < 10000000L) 7
            else 8
        else if (v < 1000000000000L)
            if (v < 10000000000L)
                if (v < 1000000000L) 9
                else 10
            else if (v < 100000000000L) 11
            else 12
        else if (v < 1000000000000000L)
            if (v < 10000000000000L) 13
            else if (v < 100000000000000L) 14
            else 15
        else if (v < 100000000000000000L)
            if (v < 10000000000000000L) 16
            else 17
        else if (v < 1000000000000000000L) 18
        else 19
    if (negative) {
        ++width
    }

    val digits = ByteArray(width)
    for (pos in width - 1 downTo if (negative) 1 else 0) {
        digits[pos] = hexDigitByte((v % 10).toInt())
        v /= 10
    }
    if (negative) {
        digits[0] = '-'.code.toByte()
    }
    this.write(digits, 0, digits.size)
}

/**
 * Writes [long] to this sink in hexadecimal form (i.e., as a string in base 16).
 *
 * Resulting string will not contain leading zeros, except the `0` value itself.
 *
 * @param long the long to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeHexadecimalUnsignedLong(long: Long) {
    var v = long
    if (v == 0L) {
        // Both a shortcut and required since the following code can't handle zero.
        this.writeByte('0'.code.toByte())
        return
    }

    val width = hexNumberLength(v)

    val digits = ByteArray(width)
    for (pos in width - 1 downTo 0) {
        digits[pos] = hexDigitByte(v.toInt().and(0xF))
        v = v ushr 4
    }
    this.write(digits, 0, digits.size)
}

/**
 * Writes am unsigned byte to this sink.
 *
 * @param byte the byte to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeUByte(byte: UByte) {
    writeByte(byte.toByte())
}

/**
 * Writes two bytes containing [short], in the big-endian order, to this sink.
 *
 * @param short the unsigned short integer to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeUShort(short: UShort) {
    writeShort(short.toShort())
}

/**
 * Writes four bytes containing [int], in the big-endian order, to this sink.
 *
 * @param int the unsigned integer to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeUInt(int: UInt) {
    writeInt(int.toInt())
}

/**
 * Writes eight bytes containing [long], in the big-endian order, to this sink.
 *
 * @param long the unsigned long integer to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeULong(long: ULong) {
    writeLong(long.toLong())
}

/**
 * Writes two bytes containing [short], in the little-endian order, to this sink.
 *
 * @param short the unsigned short integer to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeUShortLe(short: UShort) {
    writeShortLe(short.toShort())
}

/**
 * Writes four bytes containing [int], in the little-endian order, to this sink.
 *
 * @param int the unsigned integer to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeUIntLe(int: UInt) {
    writeIntLe(int.toInt())
}

/**
 * Writes eight bytes containing [long], in the little-endian order, to this sink.
 *
 * @param long the unsigned long integer to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeULongLe(long: ULong) {
    writeLongLe(long.toLong())
}

/**
 * Writes four bytes of a bit representation of [float], in the big-endian order, to this sink.
 * Bit representation of the [float] corresponds to the IEEE 754 floating-point "single format" bit layout.
 *
 * To obtain a bit representation, the [Float.toBits] function is used.
 *
 * Should be used with care when working with special values (like `NaN`) as bit patterns obtained for [Float.NaN] may vary depending on a platform.
 *
 * Note that in Kotlin/JS a value obtained by writing an original [Float] value to a [Sink] using
 * [Sink.writeFloat] and then reading it back using [Source.readFloat] may not be equal to the original value.
 * Please refer to [Float.toBits] documentation for details.
 *
 * @param float the floating point number to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeFloat(float: Float) {
    writeInt(float.toBits())
}

/**
 * Writes eight bytes of a bit representation of [double], in the big-endian order, to this sink.
 * Bit representation of the [double] corresponds to the IEEE 754 floating-point "double format" bit layout.
 *
 * To obtain a bit representation, the [Double.toBits] function is used.
 *
 * Should be used with care when working with special values (like `NaN`) as bit patterns obtained for [Double.NaN] may vary depending on a platform.
 *
 * Note that in Kotlin/JS a value obtained by writing an original [Double] value to a [Sink] using
 * [Sink.writeDouble] and then reading it back using [Source.readDouble] may not be equal to the original value.
 * Please refer to [Double.toBits] documentation for details.
 *
 * @param double the floating point number to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeDouble(double: Double) {
    writeLong(double.toBits())
}

/**
 * Writes four bytes of a bit representation of [float], in the little-endian order, to this sink.
 * Bit representation of the [float] corresponds to the IEEE 754 floating-point "single format" bit layout.
 *
 * To obtain a bit representation, the [Float.toBits] function is used.
 *
 * Should be used with care when working with special values (like `NaN`) as bit patterns obtained for [Float.NaN] may vary depending on a platform.
 *
 * Note that in Kotlin/JS a value obtained by writing an original [Float] value to a [Sink] using
 * [Sink.writeFloatLe] and then reading it back using [Source.readFloatLe] may not be equal to the original value.
 * Please refer to [Float.toBits] documentation for details.
 *
 * @param float the floating point number to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeFloatLe(float: Float) {
    writeIntLe(float.toBits())
}

/**
 * Writes eight bytes of a bit representation of [double], in the little-endian order, to this sink.
 * Bit representation of the [double] corresponds to the IEEE 754 floating-point "double format" bit layout.
 *
 * To obtain a bit representation, the [Double.toBits] function is used.
 *
 * Should be used with care when working with special values (like `NaN`) as bit patterns obtained for [Double.NaN] may vary depending on a platform.
 *
 * Note that in Kotlin/JS a value obtained by writing an original [Double] value to a [Sink] using
 * [Sink.writeDoubleLe] and then reading it back using [Source.readDoubleLe] may not be equal to the original value.
 * Please refer to [Double.toBits] documentation for details.
 *
 * @param double the floating point number to be written.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
public fun Sink.writeDoubleLe(double: Double) {
    writeLongLe(double.toBits())
}

/**
 * Provides direct access to the sink's internal buffer and hints its emit before exit.
 *
 * The internal buffer is passed into [lambda],
 * and it may be partially emitted to the underlying sink before returning from this method.
 *
 * Use this method with care as the data within the buffer is not yet emitted to the underlying sink
 * and consumption of data from the buffer will cause its loss.
 *
 * @param lambda the callback accessing internal buffer.
 *
 * @throws IllegalStateException when the sink is closed.
 * @throws IOException when some I/O error occurs.
 */
@OptIn(ExperimentalContracts::class)
public inline fun Sink.writeToInternalBuffer(lambda: (Buffer) -> Unit) {
    contract {
        callsInPlace(lambda, InvocationKind.EXACTLY_ONCE)
    }
    lambda(this.buffer)
    this.hintEmit()
}
