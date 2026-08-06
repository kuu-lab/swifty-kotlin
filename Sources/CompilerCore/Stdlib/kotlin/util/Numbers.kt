package kotlin

// KSP-646: Double/Float の isNaN / isInfinite / isFinite を bundled Kotlin へ移行する。
// 判定は IEEE 754 のビットパターンだけで完結するため、Swift ランタイム側の
// kk_{double,float}_{isNaN,isInfinite,isFinite} は削除した。生ビット取得は
// toRawBits()（NaN を正規化しない）を使う。

private const val DOUBLE_EXPONENT_MASK: Long = 0x7FF0000000000000L
private const val DOUBLE_SIGNIFICAND_MASK: Long = 0x000FFFFFFFFFFFFFL
private const val DOUBLE_MAGNITUDE_MASK: Long = 0x7FFFFFFFFFFFFFFFL

private const val FLOAT_EXPONENT_MASK: Int = 0x7F800000
private const val FLOAT_SIGNIFICAND_MASK: Int = 0x007FFFFF
private const val FLOAT_MAGNITUDE_MASK: Int = 0x7FFFFFFF

public fun Double.isNaN(): Boolean {
    val bits = this.toRawBits()
    return ((bits and DOUBLE_EXPONENT_MASK) == DOUBLE_EXPONENT_MASK) &&
        ((bits and DOUBLE_SIGNIFICAND_MASK) != 0L)
}

public fun Double.isInfinite(): Boolean =
    (this.toRawBits() and DOUBLE_MAGNITUDE_MASK) == DOUBLE_EXPONENT_MASK

public fun Double.isFinite(): Boolean =
    (this.toRawBits() and DOUBLE_EXPONENT_MASK) != DOUBLE_EXPONENT_MASK

public fun Float.isNaN(): Boolean {
    val bits = this.toRawBits()
    return ((bits and FLOAT_EXPONENT_MASK) == FLOAT_EXPONENT_MASK) &&
        ((bits and FLOAT_SIGNIFICAND_MASK) != 0)
}

public fun Float.isInfinite(): Boolean =
    (this.toRawBits() and FLOAT_MAGNITUDE_MASK) == FLOAT_EXPONENT_MASK

public fun Float.isFinite(): Boolean =
    (this.toRawBits() and FLOAT_EXPONENT_MASK) != FLOAT_EXPONENT_MASK
