package kotlin

import kswiftk.internal.*

fun Int.countOneBits(): Int = __intCountOneBits(this)

fun Int.countLeadingZeroBits(): Int = __intCountLeadingZeroBits(this)

fun Int.countTrailingZeroBits(): Int = __intCountTrailingZeroBits(this)

fun Int.highestOneBit(): Int = __intHighestOneBit(this)

fun Int.lowestOneBit(): Int = __intLowestOneBit(this)

fun Int.takeHighestOneBit(): Int = highestOneBit()

fun Int.takeLowestOneBit(): Int = lowestOneBit()

fun Int.rotateLeft(distance: Int): Int = __intRotateLeft(this, distance)

fun Int.rotateRight(distance: Int): Int = __intRotateRight(this, distance)

fun Long.highestOneBit(): Long = __longHighestOneBit(this)

fun Long.lowestOneBit(): Long = __longLowestOneBit(this)

fun Long.takeHighestOneBit(): Long = highestOneBit()

fun Long.takeLowestOneBit(): Long = lowestOneBit()

fun Long.rotateLeft(distance: Int): Long = __longRotateLeft(this, distance)

fun Long.rotateRight(distance: Int): Long = __longRotateRight(this, distance)
