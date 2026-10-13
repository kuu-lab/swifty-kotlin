package kotlin.ranges

// KSP-1283: ClosedRange cross-type contains follows the Kotlin 2.3.10 range
// conversion contract, including checked narrowing and hidden mixed-number APIs.

@kotlin.jvm.JvmName("intRangeContains")
public operator fun ClosedRange<Int>.contains(value: Byte): Boolean =
    contains(value.toInt())

@kotlin.jvm.JvmName("longRangeContains")
public operator fun ClosedRange<Long>.contains(value: Byte): Boolean =
    contains(value.toLong())

@kotlin.jvm.JvmName("shortRangeContains")
public operator fun ClosedRange<Short>.contains(value: Byte): Boolean =
    contains(value.toShort())

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("doubleRangeContains")
public operator fun ClosedRange<Double>.contains(value: Byte): Boolean =
    contains(value.toDouble())

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("floatRangeContains")
public operator fun ClosedRange<Float>.contains(value: Byte): Boolean =
    contains(value.toFloat())

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("intRangeContains")
public operator fun ClosedRange<Int>.contains(value: Double): Boolean =
    value.toIntExactOrNull()?.let { contains(it) } ?: false

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("longRangeContains")
public operator fun ClosedRange<Long>.contains(value: Double): Boolean =
    value.toLongExactOrNull()?.let { contains(it) } ?: false

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("byteRangeContains")
public operator fun ClosedRange<Byte>.contains(value: Double): Boolean =
    value.toByteExactOrNull()?.let { contains(it) } ?: false

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("shortRangeContains")
public operator fun ClosedRange<Short>.contains(value: Double): Boolean =
    value.toShortExactOrNull()?.let { contains(it) } ?: false

@kotlin.jvm.JvmName("floatRangeContains")
public operator fun ClosedRange<Float>.contains(value: Double): Boolean =
    contains(value.toFloat())

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("intRangeContains")
public operator fun ClosedRange<Int>.contains(value: Float): Boolean =
    value.toIntExactOrNull()?.let { contains(it) } ?: false

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("longRangeContains")
public operator fun ClosedRange<Long>.contains(value: Float): Boolean =
    value.toLongExactOrNull()?.let { contains(it) } ?: false

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("byteRangeContains")
public operator fun ClosedRange<Byte>.contains(value: Float): Boolean =
    value.toByteExactOrNull()?.let { contains(it) } ?: false

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("shortRangeContains")
public operator fun ClosedRange<Short>.contains(value: Float): Boolean =
    value.toShortExactOrNull()?.let { contains(it) } ?: false

@kotlin.jvm.JvmName("doubleRangeContains")
public operator fun ClosedRange<Double>.contains(value: Float): Boolean =
    contains(value.toDouble())

@kotlin.jvm.JvmName("longRangeContains")
public operator fun ClosedRange<Long>.contains(value: Int): Boolean =
    contains(value.toLong())

@kotlin.jvm.JvmName("byteRangeContains")
public operator fun ClosedRange<Byte>.contains(value: Int): Boolean =
    value.toByteExactOrNull()?.let { contains(it) } ?: false

@kotlin.jvm.JvmName("shortRangeContains")
public operator fun ClosedRange<Short>.contains(value: Int): Boolean =
    value.toShortExactOrNull()?.let { contains(it) } ?: false

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("doubleRangeContains")
public operator fun ClosedRange<Double>.contains(value: Int): Boolean =
    contains(value.toDouble())

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("floatRangeContains")
public operator fun ClosedRange<Float>.contains(value: Int): Boolean =
    contains(value.toFloat())

@kotlin.jvm.JvmName("intRangeContains")
public operator fun ClosedRange<Int>.contains(value: Long): Boolean =
    value.toIntExactOrNull()?.let { contains(it) } ?: false

@kotlin.jvm.JvmName("byteRangeContains")
public operator fun ClosedRange<Byte>.contains(value: Long): Boolean =
    value.toByteExactOrNull()?.let { contains(it) } ?: false

@kotlin.jvm.JvmName("shortRangeContains")
public operator fun ClosedRange<Short>.contains(value: Long): Boolean =
    value.toShortExactOrNull()?.let { contains(it) } ?: false

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("doubleRangeContains")
public operator fun ClosedRange<Double>.contains(value: Long): Boolean =
    contains(value.toDouble())

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("floatRangeContains")
public operator fun ClosedRange<Float>.contains(value: Long): Boolean =
    contains(value.toFloat())

@kotlin.jvm.JvmName("intRangeContains")
public operator fun ClosedRange<Int>.contains(value: Short): Boolean =
    contains(value.toInt())

@kotlin.jvm.JvmName("longRangeContains")
public operator fun ClosedRange<Long>.contains(value: Short): Boolean =
    contains(value.toLong())

@kotlin.jvm.JvmName("byteRangeContains")
public operator fun ClosedRange<Byte>.contains(value: Short): Boolean =
    value.toByteExactOrNull()?.let { contains(it) } ?: false

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("doubleRangeContains")
public operator fun ClosedRange<Double>.contains(value: Short): Boolean =
    contains(value.toDouble())

@Deprecated("This `contains` operation mixing integer and floating point arguments has ambiguous semantics and is going to be removed.")
@DeprecatedSinceKotlin(warningSince = "1.3", errorSince = "1.4", hiddenSince = "1.5")
@kotlin.jvm.JvmName("floatRangeContains")
public operator fun ClosedRange<Float>.contains(value: Short): Boolean =
    contains(value.toFloat())

internal fun Int.toByteExactOrNull(): Byte? =
    if (this in Byte.MIN_VALUE.toInt()..Byte.MAX_VALUE.toInt()) toByte() else null

internal fun Long.toByteExactOrNull(): Byte? =
    if (this in Byte.MIN_VALUE.toLong()..Byte.MAX_VALUE.toLong()) toByte() else null

internal fun Short.toByteExactOrNull(): Byte? =
    if (this in Byte.MIN_VALUE.toShort()..Byte.MAX_VALUE.toShort()) toByte() else null

internal fun Double.toByteExactOrNull(): Byte? =
    if (this in Byte.MIN_VALUE.toDouble()..Byte.MAX_VALUE.toDouble()) toInt().toByte() else null

internal fun Float.toByteExactOrNull(): Byte? =
    if (this in Byte.MIN_VALUE.toFloat()..Byte.MAX_VALUE.toFloat()) toInt().toByte() else null

internal fun Long.toIntExactOrNull(): Int? =
    if (this in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) toInt() else null

internal fun Double.toIntExactOrNull(): Int? =
    if (this in Int.MIN_VALUE.toDouble()..Int.MAX_VALUE.toDouble()) toInt() else null

internal fun Float.toIntExactOrNull(): Int? =
    if (this in Int.MIN_VALUE.toFloat()..Int.MAX_VALUE.toFloat()) toInt() else null

internal fun Double.toLongExactOrNull(): Long? =
    if (this in Long.MIN_VALUE.toDouble()..Long.MAX_VALUE.toDouble()) toLong() else null

internal fun Float.toLongExactOrNull(): Long? =
    if (this in Long.MIN_VALUE.toFloat()..Long.MAX_VALUE.toFloat()) toLong() else null

internal fun Int.toShortExactOrNull(): Short? =
    if (this in Short.MIN_VALUE.toInt()..Short.MAX_VALUE.toInt()) toShort() else null

internal fun Long.toShortExactOrNull(): Short? =
    if (this in Short.MIN_VALUE.toLong()..Short.MAX_VALUE.toLong()) toShort() else null

internal fun Double.toShortExactOrNull(): Short? =
    if (this in Short.MIN_VALUE.toDouble()..Short.MAX_VALUE.toDouble()) toInt().toShort() else null

internal fun Float.toShortExactOrNull(): Short? =
    if (this in Short.MIN_VALUE.toFloat()..Short.MAX_VALUE.toFloat()) toInt().toShort() else null
