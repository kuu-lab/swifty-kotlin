package golden.sema

fun makeDoubleArray(): DoubleArray {
    return doubleArrayOf(1.5, -2.0, 3.25)
}

fun makeDoubleArrayFromSpread(values: DoubleArray): DoubleArray {
    return doubleArrayOf(-1.0, *values, 6.0)
}

fun convertDoubleToUInt(value: Double): UInt {
    return value.toUInt()
}

fun convertDoubleToULong(value: Double): ULong {
    return value.toULong()
}
