package golden.diagnostics

// KUU-3967: only *literals* retarget to the expected unsigned type. Kotlin has
// no implicit conversion between UInt/UByte/UShort/ULong values, so an
// already-typed unsigned variable, a signed literal, or a signed value still
// fails ULong.and/or/xor/shl/shr with an argument type mismatch — matching
// kotlinc's ARGUMENT_TYPE_MISMATCH.

fun main() {
    val ul: ULong = 1uL
    val u: UInt = 1u
    val ub: UByte = 1u
    val us: UShort = 1u
    val x = 5
    val un: UInt? = 1u

    ul and u
    ul or ub
    ul xor us
    u and ub
    u or us
    ub and u
    ul and x
    ul and 5
    u and 5
    ul and un
    ul shl u
    u shl ul
    ul shl 1u
    u shl 1uL

    // Still legal: the `u`/`uL`-suffixed literal adapts to the receiver's
    // operand type, and same-type variables always apply. A shift distance
    // stays Int — `1u` cannot retarget to the signed Int parameter either.
    ul and 0xFFU
    u and 0xFFU
    ub and 0x0FU
    us or 0x0F00U
    ul and 1uL
    u and u
    ul shl 1
    u shr 1
}
