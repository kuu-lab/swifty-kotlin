/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/Blob.kt>.
 * Receiver members remain owned by their follow-up migration tasks.
 */

@file:OptIn(ExperimentalForeignApi::class)

package kotlin.native

import kotlin.collections.ByteIterator
import kotlin.internal.KsSymbolName
import kotlin.native.internal.NativePtr
import kotlinx.cinterop.ByteVar
import kotlinx.cinterop.CPointed
import kotlinx.cinterop.CPointer
import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.UByteVar

@Deprecated("ImmutableBlob is deprecated. Use ByteArray instead.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
public final class ImmutableBlob private constructor() {
    /** Returns the number of bytes in the blob. */
    public val size: Int
        get() = getArrayLength()

    // Data layout is the same as for ByteArray, so we can share native functions.
    @KsSymbolName("kk_native_byteArray_getByteAt")
    public external operator fun get(index: Int): Byte

    @KsSymbolName("__kk_byteArray_size")
    private external fun getArrayLength(): Int

    /** Creates an iterator over the elements of the array. */
    public operator fun iterator(): ByteIterator = ImmutableBlobIteratorImpl(this)
}

@Suppress("DEPRECATION_ERROR")
private class ImmutableBlobIteratorImpl(private val blob: ImmutableBlob) : ByteIterator() {
    private var index: Int = 0

    public override fun nextByte(): Byte {
        if (!hasNext()) throw NoSuchElementException("$index")
        return blob[index++]
    }

    public override operator fun hasNext(): Boolean = index < blob.size
}

/**
 * Copies the data from this blob into a new [ByteArray].
 *
 * @param startIndex the beginning (inclusive) of the subrange to copy, 0 by default.
 * @param endIndex the end (exclusive) of the subrange to copy, size of this blob by default.
 */
@Suppress("DEPRECATION_ERROR")
@Deprecated("ImmutableBlob is deprecated. Use ByteArray instead.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
public fun ImmutableBlob.toByteArray(startIndex: Int = 0, endIndex: Int = size): ByteArray {
    if (startIndex < 0 || endIndex > size || startIndex > endIndex) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, size: $size")
    }
    val result = ByteArray(endIndex - startIndex)
    for (index in startIndex until endIndex) {
        result[index - startIndex] = this[index]
    }
    return result
}

/**
 * Copies the data from this blob into a new [UByteArray].
 *
 * @param startIndex the beginning (inclusive) of the subrange to copy, 0 by default.
 * @param endIndex the end (exclusive) of the subrange to copy, size of this blob by default.
 */
@Suppress("DEPRECATION_ERROR")
@Deprecated("ImmutableBlob is deprecated. Use ByteArray instead.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
@ExperimentalUnsignedTypes
public fun ImmutableBlob.toUByteArray(startIndex: Int = 0, endIndex: Int = size): UByteArray {
    if (startIndex < 0 || endIndex > size || startIndex > endIndex) {
        throw IndexOutOfBoundsException("startIndex: $startIndex, endIndex: $endIndex, size: $size")
    }
    return UByteArray(endIndex - startIndex) { this[startIndex + it].toUByte() }
}

/**
 * Returns stable C pointer to data at certain [offset], useful as a way to pass resource
 * to C APIs.
 *
 * `ImmutableBlob` is deprecated since Kotlin 1.9. It is recommended to use `ByteArray` instead.
 * To get a stable C pointer to `ByteArray` data the array needs to be pinned first.
 * ```
 * byteArray.usePinned {
 *     val cpointer = it.addressOf(offset)
 *     // use the stable C pointer
 * }
 * ```
 * @see kotlinx.cinterop.CPointer
 */
@Suppress("DEPRECATION_ERROR")
@Deprecated("ImmutableBlob is deprecated. Use ByteArray instead. To get a stable C pointer to a `ByteArray`, pin it first.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
public fun ImmutableBlob.asCPointer(offset: Int = 0): CPointer<ByteVar> =
        __interpretCPointer<ByteVar>(asCPointerImpl(offset))!!

/**
 * Returns stable C pointer to data at certain [offset], useful as a way to pass resource
 * to C APIs.
 *
 * `ImmutableBlob` is deprecated since Kotlin 1.9. It is recommended to use `ByteArray` instead.
 * To get a stable C pointer to `ByteArray` data the array needs to be pinned first.
 * ```
 * byteArray.usePinned {
 *     val cpointer = it.addressOf(offset)
 *     // use the stable C pointer
 * }
 * ```
 * @see kotlinx.cinterop.CPointer
 */
@Suppress("DEPRECATION_ERROR")
@Deprecated("ImmutableBlob is deprecated. Use ByteArray instead. To get a stable C pointer to a `ByteArray`, pin it first.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
public fun ImmutableBlob.asUCPointer(offset: Int = 0): CPointer<UByteVar> =
        __interpretCPointer<UByteVar>(asCPointerImpl(offset))!!

// the usage site must guarantee that the receiver is kept alive long enough.
@Suppress("DEPRECATION_ERROR")
@KsSymbolName("__kk_immutable_blob_as_cpointer")
private external fun ImmutableBlob.asCPointerImpl(offset: Int): NativePtr

// KSwiftK represents C pointers as runtime handles. Reuse the existing
// cinterop handle constructor for the NativePtr-to-CPointer identity cast,
// the same role as upstream's interpretCPointer.
@KsSymbolName("kk_cpointer_new")
private external fun <T : CPointed> __interpretCPointer(rawValue: NativePtr): CPointer<T>?

@Suppress("DEPRECATION_ERROR")
@Deprecated("ImmutableBlob is deprecated. Use ByteArray instead.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
@KsSymbolName("__kk_immutable_blob_of")
public external fun immutableBlobOf(vararg elements: Short): ImmutableBlob
