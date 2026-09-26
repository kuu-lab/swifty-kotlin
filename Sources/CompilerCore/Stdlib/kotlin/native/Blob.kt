/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/Blob.kt>.
 * Receiver members remain owned by their follow-up migration tasks.
 */

package kotlin.native

import kotlin.collections.ByteIterator
import kotlin.internal.KsSymbolName

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

@Suppress("DEPRECATION_ERROR")
@Deprecated("ImmutableBlob is deprecated. Use ByteArray instead.")
@DeprecatedSinceKotlin(warningSince = "1.9", errorSince = "2.1")
public external fun immutableBlobOf(vararg elements: Short): ImmutableBlob
