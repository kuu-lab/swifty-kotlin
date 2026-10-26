/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/ranges/Progression.kt and
 * Ranges.kt.
 */

package kotlin.ranges

import kotlin.internal.KsSymbolName

// KSP-456: The runtime bridges below are private to the stdlib layer; source-backed
// operators use them only where their construction semantics still need a runtime
// handle.


@KsSymbolName("__kk_uint_rangeTo")
internal external fun __uintRangeTo(a: UInt, b: UInt): UIntRange


@KsSymbolName("__kk_ulong_rangeTo")
internal external fun __ulongRangeTo(a: ULong, b: ULong): ULongRange


@KsSymbolName("__kk_op_rangeUntil")
internal external fun __rangeUntil(a: Int, b: Int): IntRange

@KsSymbolName("__kk_long_rangeUntil")
internal external fun __rangeUntil(a: Long, b: Long): LongRange

@KsSymbolName("__kk_char_rangeUntil")
internal external fun __rangeUntil(a: Char, b: Char): CharRange

@KsSymbolName("__kk_uint_rangeUntil")
internal external fun __rangeUntil(a: UInt, b: UInt): UIntRange

@KsSymbolName("__kk_op_ulong_rangeUntil")
internal external fun __ulongRangeUntil(a: ULong, b: ULong): ULongRange


@KsSymbolName("__kk_op_step")
internal external fun __intProgressionStep(range: IntProgression, step: Int): IntProgression

@KsSymbolName("__kk_op_step")
internal external fun __intRangeStep(range: IntRange, step: Int): IntProgression

@KsSymbolName("__kk_op_step")
internal external fun __longProgressionStep(range: LongProgression, step: Int): LongProgression

@KsSymbolName("__kk_op_step")
internal external fun __longProgressionStep(range: LongProgression, step: Long): LongProgression

@KsSymbolName("__kk_op_step")
internal external fun __longRangeStep(range: LongRange, step: Int): LongProgression

@KsSymbolName("__kk_op_step")
internal external fun __longRangeStep(range: LongRange, step: Long): LongProgression

@KsSymbolName("__kk_char_range_step")
internal external fun __charProgressionStep(range: CharProgression, step: Int): CharProgression

@KsSymbolName("__kk_char_range_step")
internal external fun __charRangeStep(range: CharRange, step: Int): CharProgression

@KsSymbolName("__kk_uint_step")
internal external fun __uintProgressionStep(range: UIntProgression, step: Int): UIntProgression

@KsSymbolName("__kk_uint_step")
internal external fun __uintRangeStep(range: UIntRange, step: Int): UIntProgression


@KsSymbolName("__kk_int_progression_fromClosedRange")
internal external fun IntProgression.Companion.__intProgressionFromClosedRange(start: Int, end: Int, step: Int): IntProgression

@KsSymbolName("__kk_long_progression_fromClosedRange")
internal external fun LongProgression.Companion.__longProgressionFromClosedRange(start: Long, end: Long, step: Int): LongProgression

@KsSymbolName("__kk_long_progression_fromClosedRange")
internal external fun LongProgression.Companion.__longProgressionFromClosedRange(start: Long, end: Long, step: Long): LongProgression

@KsSymbolName("__kk_char_progression_fromClosedRange")
internal external fun CharProgression.Companion.__charProgressionFromClosedRange(start: Char, end: Char, step: Int): CharProgression

@KsSymbolName("__kk_uint_progression_fromClosedRange")
internal external fun UIntProgression.Companion.__uintProgressionFromClosedRange(start: UInt, end: UInt, step: Int): UIntProgression

@KsSymbolName("__kk_ulong_progression_fromClosedRange")
internal external fun ULongProgression.Companion.__ulongProgressionFromClosedRange(start: ULong, end: ULong, step: Int): ULongProgression

@KsSymbolName("__kk_ulong_progression_fromClosedRange")
internal external fun ULongProgression.Companion.__ulongProgressionFromClosedRange(start: ULong, end: ULong, step: Long): ULongProgression



public infix fun Byte.until(to: Byte): IntRange = __rangeUntil(this.toInt(), to.toInt())
public infix fun Byte.until(to: Short): IntRange = __rangeUntil(this.toInt(), to.toInt())
public infix fun Byte.until(to: Int): IntRange = __rangeUntil(this.toInt(), to)
public infix fun Byte.until(to: Long): LongRange = __rangeUntil(this.toLong(), to)
public infix fun Short.until(to: Byte): IntRange = __rangeUntil(this.toInt(), to.toInt())
public infix fun Short.until(to: Short): IntRange = __rangeUntil(this.toInt(), to.toInt())
public infix fun Short.until(to: Int): IntRange = __rangeUntil(this.toInt(), to)
public infix fun Short.until(to: Long): LongRange = __rangeUntil(this.toLong(), to)
public infix fun Int.until(to: Byte): IntRange = __rangeUntil(this, to.toInt())
public infix fun Int.until(to: Short): IntRange = __rangeUntil(this, to.toInt())
public infix fun Int.until(to: Int): IntRange = __rangeUntil(this, to)
public infix fun Int.until(to: Long): LongRange = __rangeUntil(this.toLong(), to)
public infix fun Long.until(to: Byte): LongRange = __rangeUntil(this, to.toLong())
public infix fun Long.until(to: Short): LongRange = __rangeUntil(this, to.toLong())
public infix fun Long.until(to: Int): LongRange = __rangeUntil(this, to.toLong())
public infix fun Long.until(to: Long): LongRange = __rangeUntil(this, to)

public operator fun Byte.rangeTo(to: Byte): IntRange = IntRange(this.toInt(), to.toInt())
public operator fun Byte.rangeTo(to: Short): IntRange = IntRange(this.toInt(), to.toInt())
public operator fun Byte.rangeTo(to: Int): IntRange = IntRange(this.toInt(), to)
public operator fun Byte.rangeTo(to: Long): LongRange = LongRange(this.toLong(), to)
public operator fun Short.rangeTo(to: Byte): IntRange = IntRange(this.toInt(), to.toInt())
public operator fun Short.rangeTo(to: Short): IntRange = IntRange(this.toInt(), to.toInt())
public operator fun Short.rangeTo(to: Int): IntRange = IntRange(this.toInt(), to)
public operator fun Short.rangeTo(to: Long): LongRange = LongRange(this.toLong(), to)
public operator fun Int.rangeTo(to: Byte): IntRange = IntRange(this, to.toInt())
public operator fun Int.rangeTo(to: Short): IntRange = IntRange(this, to.toInt())
public operator fun Int.rangeTo(to: Int): IntRange = IntRange(this, to)
public operator fun Int.rangeTo(to: Long): LongRange = LongRange(this.toLong(), to)
public operator fun Long.rangeTo(to: Byte): LongRange = LongRange(this, to.toLong())
public operator fun Long.rangeTo(to: Short): LongRange = LongRange(this, to.toLong())
public operator fun Long.rangeTo(to: Int): LongRange = LongRange(this, to.toLong())
public operator fun Long.rangeTo(to: Long): LongRange = LongRange(this, to)

public operator infix fun Byte.rangeUntil(to: Byte): IntRange = __rangeUntil(this.toInt(), to.toInt())
public operator infix fun Byte.rangeUntil(to: Short): IntRange = __rangeUntil(this.toInt(), to.toInt())
public operator infix fun Byte.rangeUntil(to: Int): IntRange = __rangeUntil(this.toInt(), to)
public operator infix fun Byte.rangeUntil(to: Long): LongRange = __rangeUntil(this.toLong(), to)
public operator infix fun Short.rangeUntil(to: Byte): IntRange = __rangeUntil(this.toInt(), to.toInt())
public operator infix fun Short.rangeUntil(to: Short): IntRange = __rangeUntil(this.toInt(), to.toInt())
public operator infix fun Short.rangeUntil(to: Int): IntRange = __rangeUntil(this.toInt(), to)
public operator infix fun Short.rangeUntil(to: Long): LongRange = __rangeUntil(this.toLong(), to)
public operator infix fun Int.rangeUntil(to: Byte): IntRange = __rangeUntil(this, to.toInt())
public operator infix fun Int.rangeUntil(to: Short): IntRange = __rangeUntil(this, to.toInt())
public operator infix fun Int.rangeUntil(to: Int): IntRange = __rangeUntil(this, to)
public operator infix fun Int.rangeUntil(to: Long): LongRange = __rangeUntil(this.toLong(), to)
public operator infix fun Long.rangeUntil(to: Byte): LongRange = __rangeUntil(this, to.toLong())
public operator infix fun Long.rangeUntil(to: Short): LongRange = __rangeUntil(this, to.toLong())
public operator infix fun Long.rangeUntil(to: Int): LongRange = __rangeUntil(this, to.toLong())
public operator infix fun Long.rangeUntil(to: Long): LongRange = __rangeUntil(this, to)

public operator infix fun Byte.downTo(to: Byte): IntProgression = IntProgression.fromClosedRange(this.toInt(), to.toInt(), -1)
public operator infix fun Byte.downTo(to: Short): IntProgression = IntProgression.fromClosedRange(this.toInt(), to.toInt(), -1)
public operator infix fun Byte.downTo(to: Int): IntProgression = IntProgression.fromClosedRange(this.toInt(), to, -1)
public operator infix fun Byte.downTo(to: Long): LongProgression = LongProgression.fromClosedRange(this.toLong(), to, -1)
public operator infix fun Short.downTo(to: Byte): IntProgression = IntProgression.fromClosedRange(this.toInt(), to.toInt(), -1)
public operator infix fun Short.downTo(to: Short): IntProgression = IntProgression.fromClosedRange(this.toInt(), to.toInt(), -1)
public operator infix fun Short.downTo(to: Int): IntProgression = IntProgression.fromClosedRange(this.toInt(), to, -1)
public operator infix fun Short.downTo(to: Long): LongProgression = LongProgression.fromClosedRange(this.toLong(), to, -1)
public operator infix fun Int.downTo(to: Byte): IntProgression = IntProgression.fromClosedRange(this, to.toInt(), -1)
public operator infix fun Int.downTo(to: Short): IntProgression = IntProgression.fromClosedRange(this, to.toInt(), -1)
public operator infix fun Int.downTo(to: Int): IntProgression = IntProgression.fromClosedRange(this, to, -1)
public operator infix fun Int.downTo(to: Long): LongProgression = LongProgression.fromClosedRange(this.toLong(), to, -1)
public operator infix fun Long.downTo(to: Byte): LongProgression = LongProgression.fromClosedRange(this, to.toLong(), -1)
public operator infix fun Long.downTo(to: Short): LongProgression = LongProgression.fromClosedRange(this, to.toLong(), -1)
public operator infix fun Long.downTo(to: Int): LongProgression = LongProgression.fromClosedRange(this, to.toLong(), -1)
public operator infix fun Long.downTo(to: Long): LongProgression = LongProgression.fromClosedRange(this, to, -1)

public operator fun Char.rangeTo(to: Char): CharRange = CharRange(this, to)
public infix fun Char.until(to: Char): CharRange = __rangeUntil(this, to)
public operator infix fun Char.rangeUntil(to: Char): CharRange = __rangeUntil(this, to)
public operator infix fun Char.downTo(to: Char): CharProgression = CharProgression.fromClosedRange(this, to, -1)

public operator fun UInt.rangeTo(to: UInt): UIntRange = __uintRangeTo(this, to)
public infix fun UInt.until(to: UInt): UIntRange = __rangeUntil(this, to)
public operator infix fun UInt.rangeUntil(to: UInt): UIntRange = __rangeUntil(this, to)
public operator infix fun UInt.downTo(to: UInt): UIntProgression = UIntProgression.fromClosedRange(this, to, -1)

public operator fun UByte.rangeTo(to: UByte): UIntRange = __uintRangeTo(this.toUInt(), to.toUInt())
public infix fun UByte.until(to: UByte): UIntRange = __rangeUntil(this.toUInt(), to.toUInt())
public operator infix fun UByte.rangeUntil(to: UByte): UIntRange = __rangeUntil(this.toUInt(), to.toUInt())
public operator infix fun UByte.downTo(to: UByte): UIntProgression =
    UIntProgression.fromClosedRange(this.toUInt(), to.toUInt(), -1)

public operator fun UShort.rangeTo(to: UShort): UIntRange = __uintRangeTo(this.toUInt(), to.toUInt())
public infix fun UShort.until(to: UShort): UIntRange = __rangeUntil(this.toUInt(), to.toUInt())
public operator infix fun UShort.rangeUntil(to: UShort): UIntRange = __rangeUntil(this.toUInt(), to.toUInt())
public operator infix fun UShort.downTo(to: UShort): UIntProgression =
    UIntProgression.fromClosedRange(this.toUInt(), to.toUInt(), -1)

public operator fun ULong.rangeTo(to: ULong): ULongRange = __ulongRangeTo(this, to)
public infix fun ULong.until(to: ULong): ULongRange = __ulongRangeUntil(this, to)
public operator infix fun ULong.rangeUntil(to: ULong): ULongRange = __ulongRangeUntil(this, to)
public operator infix fun ULong.downTo(to: ULong): ULongProgression = ULongProgression.fromClosedRange(this, to, -1)

public operator infix fun IntProgression.step(step: Int): IntProgression = __intProgressionStep(this, step)
public operator infix fun LongProgression.step(step: Int): LongProgression = __longProgressionStep(this, step)
public operator infix fun LongProgression.step(step: Long): LongProgression = __longProgressionStep(this, step)
public operator infix fun CharProgression.step(step: Int): CharProgression = __charProgressionStep(this, step)
public operator infix fun UIntProgression.step(step: Int): UIntProgression {
    require(step > 0) { "Step must be positive, was: $step." }
    return UIntProgression.fromClosedRange(first, last, if (this.step > 0) step else -step)
}
public operator infix fun ULongProgression.step(step: Int): ULongProgression {
    require(step > 0) { "Step must be positive, was: $step." }
    return ULongProgression.fromClosedRange(first, last, if (this.step > 0) step else -step)
}
public operator infix fun ULongProgression.step(step: Long): ULongProgression {
    require(step > 0L) { "Step must be positive, was: $step." }
    return ULongProgression.fromClosedRange(first, last, if (this.step > 0) step else -step)
}
public operator infix fun IntRange.step(step: Int): IntProgression = __intRangeStep(this, step)
public operator infix fun LongRange.step(step: Int): LongProgression = __longRangeStep(this, step)
public operator infix fun LongRange.step(step: Long): LongProgression = __longRangeStep(this, step)
public operator infix fun CharRange.step(step: Int): CharProgression = __charRangeStep(this, step)
public operator infix fun UIntRange.step(step: Int): UIntProgression {
    require(step > 0) { "Step must be positive, was: $step." }
    return UIntProgression.fromClosedRange(first, last, if (this.step > 0) step else -step)
}
public operator infix fun ULongRange.step(step: Int): ULongProgression {
    require(step > 0) { "Step must be positive, was: $step." }
    return ULongProgression.fromClosedRange(first, last, if (this.step > 0) step else -step)
}
public operator infix fun ULongRange.step(step: Long): ULongProgression {
    require(step > 0L) { "Step must be positive, was: $step." }
    return ULongProgression.fromClosedRange(first, last, if (this.step > 0) step else -step)
}

public fun IntProgression.Companion.fromClosedRange(start: Int, end: Int, step: Int): IntProgression = __intProgressionFromClosedRange(start, end, step)
public fun LongProgression.Companion.fromClosedRange(start: Long, end: Long, step: Int): LongProgression = __longProgressionFromClosedRange(start, end, step)
public fun LongProgression.Companion.fromClosedRange(start: Long, end: Long, step: Long): LongProgression = __longProgressionFromClosedRange(start, end, step)
public fun CharProgression.Companion.fromClosedRange(start: Char, end: Char, step: Int): CharProgression = __charProgressionFromClosedRange(start, end, step)
public fun UIntProgression.Companion.fromClosedRange(start: UInt, end: UInt, step: Int): UIntProgression = __uintProgressionFromClosedRange(start, end, step)
public fun ULongProgression.Companion.fromClosedRange(start: ULong, end: ULong, step: Int): ULongProgression = __ulongProgressionFromClosedRange(start, end, step)
public fun ULongProgression.Companion.fromClosedRange(start: ULong, end: ULong, step: Long): ULongProgression = __ulongProgressionFromClosedRange(start, end, step)
