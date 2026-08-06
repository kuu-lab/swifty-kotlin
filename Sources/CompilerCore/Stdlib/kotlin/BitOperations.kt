package kotlin

// KSP-643: countOneBits / countLeadingZeroBits / countTrailingZeroBits.
// Pure Kotlin implementations for Int and Long (SWAR popcount).

public fun Int.countOneBits(): Int {
    var v = this
    v -= (v ushr 1) and 0x55555555
    v = (v and 0x33333333) + ((v ushr 2) and 0x33333333)
    v = (v + (v ushr 4)) and 0x0F0F0F0F
    v += v ushr 8
    v += v ushr 16
    return v and 0x3F
}

public fun Int.countLeadingZeroBits(): Int {
    var v = this
    v = v or (v ushr 1)
    v = v or (v ushr 2)
    v = v or (v ushr 4)
    v = v or (v ushr 8)
    v = v or (v ushr 16)
    return v.inv().countOneBits()
}

public fun Int.countTrailingZeroBits(): Int {
    if (this == 0) return 32
    return ((this and (-this)) - 1).countOneBits()
}

public fun Long.countOneBits(): Int {
    var v = this
    v -= (v ushr 1) and 0x5555555555555555L
    v = (v and 0x3333333333333333L) + ((v ushr 2) and 0x3333333333333333L)
    v = (v + (v ushr 4)) and 0x0F0F0F0F0F0F0F0FL
    v += v ushr 8
    v += v ushr 16
    v += v ushr 32
    return (v and 0x7FL).toInt()
}

public fun Long.countLeadingZeroBits(): Int {
    var v = this
    v = v or (v ushr 1)
    v = v or (v ushr 2)
    v = v or (v ushr 4)
    v = v or (v ushr 8)
    v = v or (v ushr 16)
    v = v or (v ushr 32)
    return v.inv().countOneBits()
}

public fun Long.countTrailingZeroBits(): Int {
    if (this == 0L) return 64
    return ((this and (-this)) - 1L).countOneBits()
}
