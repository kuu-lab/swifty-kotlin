/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/random/URandom.kt.
 */

package kotlin.random

// KSP-466: nextUBytes, ported from kotlin-stdlib
// (libraries/stdlib/src/kotlin/random/URandom.kt). nextUInt/nextULong (scalar
// overloads) live as real members on Random itself (Random.kt) rather than as
// package-level extensions here — see the comment above their declaration.
//
// Range-argument overloads (nextUInt(UIntRange) / nextULong(ULongRange) live as
// source-backed members on Random.kt. Their retained runtime engines are
// private __kk_random_* bridges, matching nextInt(IntRange)/nextLong(LongRange).

public fun Random.nextUBytes(array: UByteArray): UByteArray {
    nextBytes(array.asByteArray())
    return array
}

public fun Random.nextUBytes(size: Int): UByteArray = nextBytes(size).asUByteArray()

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
