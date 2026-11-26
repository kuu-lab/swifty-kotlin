/*
 * Copyright 2017-2024 JetBrains s.r.o. and respective authors and developers.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENCE file.
 */

package kotlinx.io.bytestring

import kotlinx.cinterop.*
import kotlinx.io.bytestring.unsafe.UnsafeByteStringApi
import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations
import platform.Foundation.NSData
import platform.Foundation.create

@OptIn(UnsafeNumber::class, BetaInteropApi::class, ExperimentalForeignApi::class)
public fun ByteString.toNSData(): NSData {
    if (isEmpty()) {
        return NSData()
    }
    val data = getBackingArrayReference()
    return data.usePinned {
        NSData.create(bytes = it.addressOf(0), length = data.size.toULong())
    }
}

@OptIn(ExperimentalForeignApi::class, UnsafeNumber::class, UnsafeByteStringApi::class)
public fun NSData.toByteString(): ByteString {
    val l = length.toLong()
    if (l == 0L) {
        return ByteString.EMPTY
    }
    if (l > Int.MAX_VALUE) {
        throw IllegalArgumentException("NSData content is to long to read as byte array: $l")
    }
    return UnsafeByteStringOperations.wrapUnsafe(
        bytes!!.readBytes(l.toInt())
    )
}
