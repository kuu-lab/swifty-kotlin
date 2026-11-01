package kotlin

import kotlin.internal.KsSymbolName
import kotlin.text.__charFromCode

// KSP-1539: Char values carry their UTF-16 code unit as the underlying Int
// representation, so the conversion bodies can be expressed through Char.code
// and the existing primitive conversion members.

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

@Deprecated(
    "Conversion of Char to Number is deprecated. Use Char.code property instead.",
    ReplaceWith("this.code.toFloat()")
)
@DeprecatedSinceKotlin(warningSince = "1.5")
public fun Char.toFloat(): Float = this.code.toFloat()

// KSP-642: rotateLeft / rotateRight は shl / ushr / or の合成だけで表現でき、
// ランタイムブリッジを必要としない。
// shl / shr / ushr は Kotlin 本家と同じくシフト量を Int で 5bit・Long で 6bit に
// マスクするため、bitCount が 0・負値・幅超過でも本家と同じ結果になる。

// KUU-2094: Source declarations expose primitive shift intrinsics to implicit
// receiver calls such as `shr(bitCount)` inside an Int or Long extension.
public infix fun Int.shl(bitCount: Int): Int = this shl bitCount

public infix fun Int.shr(bitCount: Int): Int = this shr bitCount

public infix fun Int.ushr(bitCount: Int): Int = this ushr bitCount

public infix fun Long.shl(bitCount: Int): Long = this shl bitCount

public infix fun Long.shr(bitCount: Int): Long = this shr bitCount

public infix fun Long.ushr(bitCount: Int): Long = this ushr bitCount

public fun Int.rotateLeft(bitCount: Int): Int =
    (this shl bitCount) or (this ushr (32 - bitCount))

public fun Int.rotateRight(bitCount: Int): Int =
    (this shl (32 - bitCount)) or (this ushr bitCount)

public fun Long.rotateLeft(bitCount: Int): Long =
    (this shl bitCount) or (this ushr (64 - bitCount))

public fun Long.rotateRight(bitCount: Int): Long =
    (this shl (64 - bitCount)) or (this ushr bitCount)

// KUU-4103: upstream declares and/or/xor/inv (and shl/shr for UInt/ULong) as
// members on the integer types. Their bodies still bind through the primitive
// fast path; the declarations exist so member-style calls resolve against the
// public kotlin.* surface instead of falling to package-internal helpers such
// as kotlinx.io's `internal infix fun Int.and(other: Long)`.
public infix fun Int.and(other: Int): Int = this and other

public infix fun Int.or(other: Int): Int = this or other

public infix fun Int.xor(other: Int): Int = this xor other

public fun Int.inv(): Int = this.inv()

public infix fun Long.and(other: Long): Long = this and other

public infix fun Long.or(other: Long): Long = this or other

public infix fun Long.xor(other: Long): Long = this xor other

public fun Long.inv(): Long = this.inv()

public infix fun UInt.and(other: UInt): UInt = this and other

public infix fun UInt.or(other: UInt): UInt = this or other

public infix fun UInt.xor(other: UInt): UInt = this xor other

public fun UInt.inv(): UInt = this.inv()

public infix fun UInt.shl(bitCount: Int): UInt = this shl bitCount

public infix fun UInt.shr(bitCount: Int): UInt = this shr bitCount

public infix fun ULong.and(other: ULong): ULong = this and other

public infix fun ULong.or(other: ULong): ULong = this or other

public infix fun ULong.xor(other: ULong): ULong = this xor other

public fun ULong.inv(): ULong = this.inv()

public infix fun ULong.shl(bitCount: Int): ULong = this shl bitCount

public infix fun ULong.shr(bitCount: Int): ULong = this shr bitCount

public infix fun UByte.and(other: UByte): UByte = this and other

public infix fun UByte.or(other: UByte): UByte = this or other

public infix fun UByte.xor(other: UByte): UByte = this xor other

public fun UByte.inv(): UByte = this.inv()

public infix fun UShort.and(other: UShort): UShort = this and other

public infix fun UShort.or(other: UShort): UShort = this or other

public infix fun UShort.xor(other: UShort): UShort = this xor other

public fun UShort.inv(): UShort = this.inv()

// KSP-1536: The runtime bridges remain internal representation support: Char
// uses the existing code-unit constructor bridge, while Double uses the IEEE
// payload bridge required by the current primitive representation.

@KsSymbolName("kk_int_to_double_bits")
@PublishedApi
internal external fun __intToDouble(value: Int): Double

public inline fun Int.toChar(): Char = __charFromCode(this)

public inline fun Int.toDouble(): Double = __intToDouble(this)

@Deprecated(
    "Direct conversion to Char is deprecated. Use toInt().toChar() or Char constructor instead.",
    ReplaceWith("this.toInt().toChar()")
)
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.3")
public fun Long.toChar(): Char = this.toInt().toChar()

// KUU-3763: Byte/Short.toChar carry the same upstream deprecation as
// Long.toChar (warning since 1.5, error since 2.3). They are declared as
// package extensions so `checkBuiltinDeprecation` can read their metadata for
// the explicit primitive-receiver fast path; the calls themselves still lower
// through the primitive conversion path.
@Deprecated(
    "Direct conversion to Char is deprecated. Use toInt().toChar() or Char constructor instead.",
    ReplaceWith("this.toInt().toChar()")
)
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.3")
public fun Byte.toChar(): Char = this.toInt().toChar()

@Deprecated(
    "Direct conversion to Char is deprecated. Use toInt().toChar() or Char constructor instead.",
    ReplaceWith("this.toInt().toChar()")
)
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.3")
public fun Short.toChar(): Char = this.toInt().toChar()

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

// KSP-1538: The hidden bridges only carry the IEEE payload across the raw KIR
// ABI; the public conversion members below own Kotlin's saturation and
// truncation contract. Float/Double.toChar intentionally compose through
// toInt().
@KsSymbolName("__kk_double_to_int")
private external fun __doubleToInt(value: Double): Int

@KsSymbolName("__kk_double_to_long")
private external fun __doubleToLong(value: Double): Long

@KsSymbolName("__kk_float_to_int")
private external fun __floatToInt(value: Float): Int

@KsSymbolName("__kk_float_to_long")
private external fun __floatToLong(value: Float): Long

@KsSymbolName("__kk_float_to_double_bits")
private external fun __floatToDouble(value: Float): Double

public fun Double.toInt(): Int = __doubleToInt(this)

public fun Double.toLong(): Long = __doubleToLong(this)

@Deprecated(
    "Direct conversion to Char is deprecated. Use toInt().toChar() or Char constructor instead.",
    ReplaceWith("this.toInt().toChar()")
)
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.3")
public fun Double.toChar(): Char = toInt().toChar()

public fun Float.toInt(): Int = __floatToInt(this)

public fun Float.toLong(): Long = __floatToLong(this)

public fun Float.toDouble(): Double = __floatToDouble(this)

@Deprecated(
    "Direct conversion to Char is deprecated. Use toInt().toChar() or Char constructor instead.",
    ReplaceWith("this.toInt().toChar()")
)
@DeprecatedSinceKotlin(warningSince = "1.5", errorSince = "2.3")
public fun Float.toChar(): Char = toInt().toChar()

// KSP-1544 (KUU-588): Float/Double narrowing to Byte/Short is defined by the
// stdlib as `toInt().toByte()` / `toInt().toShort()` and deprecated at error
// level since Kotlin 1.5.

@Deprecated(
    "Unclear conversion. To achieve the same result convert to Int explicitly and then to Byte.",
    ReplaceWith("toInt().toByte()")
)
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.5")
public fun Double.toByte(): Byte = toInt().toByte()

@Deprecated(
    "Unclear conversion. To achieve the same result convert to Int explicitly and then to Short.",
    ReplaceWith("toInt().toShort()")
)
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.5")
public fun Double.toShort(): Short = toInt().toShort()

@Deprecated(
    "Unclear conversion. To achieve the same result convert to Int explicitly and then to Byte.",
    ReplaceWith("toInt().toByte()")
)
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.5")
public fun Float.toByte(): Byte = toInt().toByte()

@Deprecated(
    "Unclear conversion. To achieve the same result convert to Int explicitly and then to Short.",
    ReplaceWith("toInt().toShort()")
)
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.5")
public fun Float.toShort(): Short = toInt().toShort()
