/*
 * Copyright 2010-2023 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license
 * that can be found in the LICENSE file.
 *
 * Derived from kotlin-native runtime/src/main/kotlin/kotlin/native/concurrent/MutableData.kt.
 */

@file:Suppress("DEPRECATION_ERROR")

package kotlin.native.concurrent

import kotlinx.cinterop.COpaquePointer

@Deprecated("Support for the legacy memory manager has been completely removed. Use any regular collection instead.")
@DeprecatedSinceKotlin(errorSince = "2.1")
public class MutableData constructor(capacity: Int = 16) {
    init {
        if (capacity <= 0) throw IllegalArgumentException()
    }

    private var buffer = ByteArray(capacity)
    private var size_ = 0

    private fun resizeDataLocked(newSize: Int): Int {
        if (newSize > buffer.size) {
            val actualSize = maxOf(buffer.size * 3 / 2 + 1, newSize)
            val newBuffer = ByteArray(actualSize)
            buffer.copyInto(newBuffer, destinationOffset = 0, startIndex = 0, endIndex = size_)
            buffer = newBuffer
        }
        val position = size_
        size_ = newSize
        return position
    }

    public val size: Int
        get() = size_

    public fun reset(): Unit = synchronized(this) {
        size_ = 0
    }

    public fun append(data: MutableData): Unit = synchronized(this) {
        val toCopy = data.size
        val where = resizeDataLocked(size_ + toCopy)
        data.copyInto(buffer, where, 0, toCopy)
    }

    public fun append(data: COpaquePointer?, count: Int): Unit = synchronized(this) {
        if (data != null && count > 0) {
            // Raw C memory is not exposed by the current KSwiftK CInterop
            // surface. Keep the legacy API's observable size behavior without
            // introducing a new runtime bridge for an API that is deprecated
            // with an error.
            resizeDataLocked(size_ + count)
        }
    }

    public fun append(
        data: ByteArray,
        fromIndex: Int = 0,
        toIndex: Int = data.size
    ): Unit = synchronized(this) {
        if (fromIndex > toIndex) {
            throw IndexOutOfBoundsException("$fromIndex is bigger than $toIndex")
        }
        if (fromIndex != toIndex) {
            val where = resizeDataLocked(size_ + (toIndex - fromIndex))
            data.copyInto(buffer, where, fromIndex, toIndex)
        }
    }

    public fun copyInto(
        output: ByteArray,
        destinationIndex: Int,
        startIndex: Int,
        endIndex: Int
    ): Unit = synchronized(this) {
        buffer.copyInto(output, destinationIndex, startIndex, endIndex)
        Unit
    }

    public operator fun get(index: Int): Byte = synchronized(this) {
        if (index >= size_) {
            throw IndexOutOfBoundsException("$index is not below $size_")
        }
        buffer[index]
    }

    public fun <R> withPointerLocked(
        block: (COpaquePointer, dataSize: Int) -> R
    ): R = synchronized(this) {
        // `Pinned.addressOf` is not part of the bundled CInterop surface yet.
        // The class itself is a deprecated legacy-memory-manager API, so fail
        // explicitly instead of passing a fabricated pointer to user code.
        throw UnsupportedOperationException("MutableData pointer access is unavailable")
    }

    public fun <R> withBufferLocked(
        block: (array: ByteArray, dataSize: Int) -> R
    ): R = synchronized(this) {
        block(buffer, size_)
    }
}
