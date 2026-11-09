@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.random.Random

// Keep range random operations on their dedicated runtime bridges. Routing
// these through Random.nextInt/nextLong(range) changes seeded JVM parity.
@KsSymbolName("__kk_range_random")
private external fun __kk_intRangeRandom(range: IntRange): Int

@KsSymbolName("__kk_range_random_random")
private external fun __kk_intRangeRandomRandom(range: IntRange, random: Random): Int

@KsSymbolName("__kk_range_randomOrNull")
private external fun __kk_intRangeRandomOrNull(range: IntRange): Int?

@KsSymbolName("__kk_range_randomOrNull_random")
private external fun __kk_intRangeRandomOrNullRandom(range: IntRange, random: Random): Int?

@KsSymbolName("__kk_long_range_random")
private external fun __kk_longRangeRandom(range: LongRange): Long

@KsSymbolName("__kk_long_range_random_random")
private external fun __kk_longRangeRandomRandom(range: LongRange, random: Random): Long

@KsSymbolName("__kk_long_range_randomOrNull")
private external fun __kk_longRangeRandomOrNull(range: LongRange): Long?

@KsSymbolName("__kk_long_range_randomOrNull_random")
private external fun __kk_longRangeRandomOrNullRandom(range: LongRange, random: Random): Long?

@KsSymbolName("__kk_char_range_random")
private external fun __kk_charRangeRandom(range: CharRange): Char

@KsSymbolName("__kk_char_range_random_random")
private external fun __kk_charRangeRandomRandom(range: CharRange, random: Random): Char

@KsSymbolName("__kk_char_range_randomOrNull")
private external fun __kk_charRangeRandomOrNull(range: CharRange): Char?

@KsSymbolName("__kk_char_range_randomOrNull_random")
private external fun __kk_charRangeRandomOrNullRandom(range: CharRange, random: Random): Char?

@KsSymbolName("__kk_uint_range_random")
private external fun __kk_uintRangeRandom(range: UIntRange): UInt

@KsSymbolName("__kk_uint_range_random_random")
private external fun __kk_uintRangeRandomRandom(range: UIntRange, random: Random): UInt

@KsSymbolName("__kk_uint_range_randomOrNull")
private external fun __kk_uintRangeRandomOrNull(range: UIntRange): UInt?

@KsSymbolName("__kk_uint_range_randomOrNull_random")
private external fun __kk_uintRangeRandomOrNullRandom(range: UIntRange, random: Random): UInt?

@KsSymbolName("__kk_ulong_range_random")
private external fun __kk_ulongRangeRandom(range: ULongRange): ULong

@KsSymbolName("__kk_ulong_range_random_random")
private external fun __kk_ulongRangeRandomRandom(range: ULongRange, random: Random): ULong

@KsSymbolName("__kk_ulong_range_randomOrNull")
private external fun __kk_ulongRangeRandomOrNull(range: ULongRange): ULong?

@KsSymbolName("__kk_ulong_range_randomOrNull_random")
private external fun __kk_ulongRangeRandomOrNullRandom(range: ULongRange, random: Random): ULong?

public fun IntRange.random(): Int = __kk_intRangeRandom(this)
public fun IntRange.random(random: Random): Int = __kk_intRangeRandomRandom(this, random)
public fun IntRange.randomOrNull(): Int? = __kk_intRangeRandomOrNull(this)
public fun IntRange.randomOrNull(random: Random): Int? = __kk_intRangeRandomOrNullRandom(this, random)

public fun LongRange.random(): Long = __kk_longRangeRandom(this)
public fun LongRange.random(random: Random): Long = __kk_longRangeRandomRandom(this, random)
public fun LongRange.randomOrNull(): Long? = __kk_longRangeRandomOrNull(this)
public fun LongRange.randomOrNull(random: Random): Long? = __kk_longRangeRandomOrNullRandom(this, random)

public fun CharRange.random(): Char = __kk_charRangeRandom(this)
public fun CharRange.random(random: Random): Char = __kk_charRangeRandomRandom(this, random)
public fun CharRange.randomOrNull(): Char? = __kk_charRangeRandomOrNull(this)
public fun CharRange.randomOrNull(random: Random): Char? = __kk_charRangeRandomOrNullRandom(this, random)

public fun UIntRange.random(): UInt = __kk_uintRangeRandom(this)
public fun UIntRange.random(random: Random): UInt = __kk_uintRangeRandomRandom(this, random)
public fun UIntRange.randomOrNull(): UInt? = __kk_uintRangeRandomOrNull(this)
public fun UIntRange.randomOrNull(random: Random): UInt? = __kk_uintRangeRandomOrNullRandom(this, random)

public fun ULongRange.random(): ULong = __kk_ulongRangeRandom(this)
public fun ULongRange.random(random: Random): ULong = __kk_ulongRangeRandomRandom(this, random)
public fun ULongRange.randomOrNull(): ULong? = __kk_ulongRangeRandomOrNull(this)
public fun ULongRange.randomOrNull(random: Random): ULong? = __kk_ulongRangeRandomOrNullRandom(this, random)
