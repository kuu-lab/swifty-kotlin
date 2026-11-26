/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Adapted from kotlinx-io 0.9.1 bytestring/common/src/Base64.kt.
 */
package kotlinx.io.bytestring

import kotlin.io.encoding.Base64

public fun Base64.encodeToByteArray(source: ByteString, startIndex: Int = 0, endIndex: Int = source.size): ByteArray {
    return encodeToByteArray(source.getBackingArrayReference(), startIndex, endIndex)
}

public fun Base64.encodeIntoByteArray(
    source: ByteString,
    destination: ByteArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = source.size
): Int {
    return encodeIntoByteArray(source.getBackingArrayReference(), destination, destinationOffset, startIndex, endIndex)
}

public fun Base64.encode(
    source: ByteString,
    startIndex: Int = 0,
    endIndex: Int = source.size
): String {
    return encode(source.getBackingArrayReference(), startIndex, endIndex)
}

@IgnorableReturnValue
public fun <A : Appendable> Base64.encodeToAppendable(
    source: ByteString,
    destination: A,
    startIndex: Int = 0,
    endIndex: Int = source.size
): A {
    return encodeToAppendable(source.getBackingArrayReference(), destination, startIndex, endIndex)
}


public fun Base64.decode(source: ByteString, startIndex: Int = 0, endIndex: Int = source.size): ByteArray {
    return decode(source.getBackingArrayReference(), startIndex, endIndex)
}

public fun Base64.decodeToByteString(source: CharSequence, startIndex: Int = 0, endIndex: Int = source.length): ByteString {
    return ByteString.wrap(decode(source, startIndex, endIndex))
}

public fun Base64.decodeIntoByteArray(
    source: ByteString,
    destination: ByteArray,
    destinationOffset: Int = 0,
    startIndex: Int = 0,
    endIndex: Int = source.size
): Int {
    return decodeIntoByteArray(source.getBackingArrayReference(), destination, destinationOffset, startIndex, endIndex)
}

public fun Base64.decodeToByteString(source: ByteArray, startIndex: Int = 0, endIndex: Int = source.size): ByteString {
    return ByteString.wrap(decode(source, startIndex, endIndex))
}

public fun Base64.decodeToByteString(source: ByteString, startIndex: Int = 0, endIndex: Int = source.size): ByteString {
    return ByteString.wrap(decode(source.getBackingArrayReference(), startIndex, endIndex))
}
