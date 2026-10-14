/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/random/URandom.kt.
 */

package kotlin.random

import kotlin.internal.KsSymbolName

// Unsigned random APIs are package extensions, matching kotlin-stdlib.
// Keep the existing range engines behind private bridges.
@KsSymbolName("__kk_random_nextUInt_uintRange")
private external fun __kk_random_nextUInt_uintRange(random: Random, range: UIntRange): UInt

@KsSymbolName("__kk_random_nextULong_ulongRange")
private external fun __kk_random_nextULong_ulongRange(random: Random, range: ULongRange): ULong

public fun Random.nextUInt(): UInt = nextInt().toUInt()

public fun Random.nextUInt(until: UInt): UInt = nextUInt(0u, until)

public fun Random.nextUInt(from: UInt, until: UInt): UInt {
    checkUIntRangeBounds(from, until)
    val signedFrom = from.toInt() xor Int.MIN_VALUE
    val signedUntil = until.toInt() xor Int.MIN_VALUE
    val signedResult = nextInt(signedFrom, signedUntil) xor Int.MIN_VALUE
    return signedResult.toUInt()
}

public fun Random.nextUInt(range: UIntRange): UInt = __kk_random_nextUInt_uintRange(this, range)

public fun Random.nextULong(): ULong = nextLong().toULong()

public fun Random.nextULong(until: ULong): ULong = nextULong(0uL, until)

public fun Random.nextULong(from: ULong, until: ULong): ULong {
    checkULongRangeBounds(from, until)
    val signedFrom = from.toLong() xor Long.MIN_VALUE
    val signedUntil = until.toLong() xor Long.MIN_VALUE
    val signedResult = nextLong(signedFrom, signedUntil) xor Long.MIN_VALUE
    return signedResult.toULong()
}

public fun Random.nextULong(range: ULongRange): ULong = __kk_random_nextULong_ulongRange(this, range)

@ExperimentalUnsignedTypes
public fun Random.nextUBytes(array: UByteArray): UByteArray {
    nextBytes(array.asByteArray())
    return array
}

@ExperimentalUnsignedTypes
public fun Random.nextUBytes(size: Int): UByteArray = nextBytes(size).asUByteArray()

@ExperimentalUnsignedTypes
public fun Random.nextUBytes(array: UByteArray, fromIndex: Int, toIndex: Int): UByteArray {
    nextBytes(array.asByteArray(), fromIndex, toIndex)
    return array
}

// See checkRangeBounds in Random.kt for why the message is precomputed.
internal fun checkUIntRangeBounds(from: UInt, until: UInt) {
    val message = boundsErrorMessage(from, until)
    require(until > from) { message }
}

internal fun checkULongRangeBounds(from: ULong, until: ULong) {
    val message = boundsErrorMessage(from, until)
    require(until > from) { message }
}
