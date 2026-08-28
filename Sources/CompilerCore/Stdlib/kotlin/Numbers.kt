package kotlin

import kotlin.internal.KsSymbolName

// KSP-1539: Char numeric conversions are source-backed. Char values carry
// their UTF-16 code unit as the underlying Int representation, so the
// conversion bodies can be expressed through Char.code and the existing
// primitive conversion members.

@Deprecated(
    "Conversion of Char to Number is deprecated. Use Char.code property instead.",
    ReplaceWith("this.code.toByte()")
)
@DeprecatedSinceKotlin(warningSince = "1.5")
public fun Char.toByte(): Byte = this.code.toByte()

@Deprecated(
    "Conversion of Char to Number is deprecated. Use Char.code property instead.",
    ReplaceWith("this.code.toShort()")
)
@DeprecatedSinceKotlin(warningSince = "1.5")
public fun Char.toShort(): Short = this.code.toShort()

@Deprecated(
    "Conversion of Char to Number is deprecated. Use Char.code property instead.",
    ReplaceWith("this.code")
)
@DeprecatedSinceKotlin(warningSince = "1.5")
public fun Char.toInt(): Int = this.code

@Deprecated(
    "Conversion of Char to Number is deprecated. Use Char.code property instead.",
    ReplaceWith("this.code.toLong()")
)
@DeprecatedSinceKotlin(warningSince = "1.5")
public fun Char.toLong(): Long = this.code.toLong()

// KSP-642: rotateLeft / rotateRight は shl / ushr / or の合成だけで表現でき、
// ランタイムブリッジを必要としない（kk_int_rotateLeft 等 4 関数を削除）。
// shl / shr / ushr は Kotlin 本家と同じくシフト量を Int で 5bit・Long で 6bit に
// マスクするため、bitCount が 0・負値・幅超過でも本家と同じ結果になる。

public fun Int.rotateLeft(bitCount: Int): Int =
    (this shl bitCount) or (this ushr (32 - bitCount))

public fun Int.rotateRight(bitCount: Int): Int =
    (this shl (32 - bitCount)) or (this ushr bitCount)

public fun Long.rotateLeft(bitCount: Int): Long =
    (this shl bitCount) or (this ushr (64 - bitCount))

public fun Long.rotateRight(bitCount: Int): Long =
    (this shl (64 - bitCount)) or (this ushr bitCount)

// KSP-647: Floating-point bit-pattern conversions keep the ABI-specific
// reinterpretation in the runtime while exposing the public API as Kotlin.

@KsSymbolName("__kk_double_toBits")
internal external fun __doubleToBits(value: Double): Long

@KsSymbolName("__kk_double_toRawBits")
internal external fun __doubleToRawBits(value: Double): Long

@KsSymbolName("__kk_float_toBits")
internal external fun __floatToBits(value: Float): Int

@KsSymbolName("__kk_float_toRawBits")
internal external fun __floatToRawBits(value: Float): Int

public fun Double.toBits(): Long = __doubleToBits(this)

public fun Double.toRawBits(): Long = __doubleToRawBits(this)

public fun Float.toBits(): Int = __floatToBits(this)

public fun Float.toRawBits(): Int = __floatToRawBits(this)
