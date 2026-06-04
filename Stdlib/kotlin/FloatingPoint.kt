package kotlin

import kswiftk.internal.*

fun Double.isNaN(): Boolean = __doubleIsNaN(this)

fun Double.isInfinite(): Boolean = __doubleIsInfinite(this)

fun Double.isFinite(): Boolean = !isNaN() && !isInfinite()

fun Float.isNaN(): Boolean = __floatIsNaN(this)

fun Float.isInfinite(): Boolean = __floatIsInfinite(this)

fun Float.isFinite(): Boolean = !isNaN() && !isInfinite()

fun Double.toBits(): Long = __doubleToBits(this)

fun Double.toRawBits(): Long = __doubleToRawBits(this)

fun Float.toBits(): Int = __floatToBits(this)

fun Float.toRawBits(): Int = __floatToRawBits(this)
