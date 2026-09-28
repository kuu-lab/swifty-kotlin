/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Adapted from kotlinx-io 0.9.1 bytestring/common/src/ByteStringBuilder.kt.
 */
package kotlinx.io.bytestring

/** A growable byte sequence for creating immutable [ByteString] values. */
public class ByteStringBuilder(initialCapacity: Int = 0) {
    private var buffer: ByteArray = ByteArray(initialCapacity)
    private var offset: Int = 0

    public val size: Int get() = offset
    public val capacity: Int get() = buffer.size

    public fun toByteString(): ByteString {
        if (size == 0) return ByteString()
        // Copy even at full capacity: further append calls must not change
        // an already returned immutable value.
        return ByteString(buffer, 0, size)
    }

    public fun toByteArray(): ByteArray = buffer.copyOfRange(0, size)

    public fun append(byte: Byte) {
        ensureCapacity(offset + 1)
        buffer[offset] = byte
        offset++
    }

    // Keep the one- and two-argument overloads explicit. The compiler also
    // sees the extension append(vararg Byte), and the defaulted array member
    // can otherwise leave append(ByteArray) without a viable overload.
    public fun append(array: ByteArray) {
        append(array, 0, array.size)
    }

    public fun append(array: ByteArray, startIndex: Int) {
        append(array, startIndex, array.size)
    }

    public fun append(array: ByteArray, startIndex: Int = 0, endIndex: Int = array.size) {
        require(startIndex <= endIndex) { "startIndex ($startIndex) > endIndex ($endIndex)" }
        if (startIndex < 0 || endIndex > array.size) {
            throw IndexOutOfBoundsException("startIndex ($startIndex) and endIndex ($endIndex) out of bounds")
        }
        ensureCapacity(offset + endIndex - startIndex)
        array.copyInto(buffer, offset, startIndex, endIndex)
        offset += endIndex - startIndex
    }

    private fun ensureCapacity(requiredCapacity: Int) {
        if (buffer.size >= requiredCapacity) return
        var capacity = if (buffer.size == 0) 16 else buffer.size + buffer.size / 2
        if (capacity < requiredCapacity) capacity = requiredCapacity
        val enlarged = ByteArray(capacity)
        buffer.copyInto(enlarged)
        buffer = enlarged
    }
}

public fun ByteStringBuilder.append(byte: UByte): Unit = append(byte.toByte())
public fun ByteStringBuilder.append(byteString: ByteString): Unit =
    append(byteString.getBackingArrayReference())

public fun ByteStringBuilder.append(vararg bytes: Byte) {
    for (byte in bytes) append(byte)
}

public inline fun buildByteString(
    capacity: Int = 0,
    builderAction: ByteStringBuilder.() -> Unit
): ByteString = ByteStringBuilder(capacity).apply(builderAction).toByteString()
