package golden.sema

import kotlin.math.E

fun readE(): Double = E

fun readECopy(): Double {
    val copied = E
    return copied
}

fun readERawBits(): Long = E.toRawBits()
