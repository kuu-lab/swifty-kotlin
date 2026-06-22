package kotlin

import kswiftk.internal.*

fun Double.isNaN(): Boolean = this != this

fun Double.isInfinite(): Boolean = this == Double.POSITIVE_INFINITY || this == Double.NEGATIVE_INFINITY

fun Double.isFinite(): Boolean = !isNaN() && !isInfinite()

fun Float.isNaN(): Boolean = this != this

fun Float.isInfinite(): Boolean = this == Float.POSITIVE_INFINITY || this == Float.NEGATIVE_INFINITY

fun Float.isFinite(): Boolean = !isNaN() && !isInfinite()

fun Double.toBits(): Long = __doubleToBits(this)

fun Double.toRawBits(): Long = __doubleToRawBits(this)

fun Float.toBits(): Int = __floatToBits(this)

fun Float.toRawBits(): Int = __floatToRawBits(this)
