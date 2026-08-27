package golden.sema

fun uintFromInt(): UInt {
    val zero = UInt(0)
    val one = UInt(1)
    val allBits = UInt(-1)
    val min = UInt(Int.MIN_VALUE)
    val max = UInt(Int.MAX_VALUE)
    return zero + one + allBits + min + max
}

fun inferredUInt(): UInt = UInt(-1)

fun boxedUInt(): Any = UInt(-1)

fun isUInt(value: Any): Boolean = value is UInt
