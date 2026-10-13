@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.internal.KsSymbolName
import kotlin.native.NoInline
import kotlin.random.Random

// MIGRATION-RANGE-002
// Range/Progression higher-order functions migrated to Kotlin source.
// Migration source:
//   Sources/Runtime/RuntimeRangeAndDispatch.swift, RuntimeRangeIntRangeHOF.swift,
//   RuntimeRangeLongRange.swift, RuntimeRangeSharedHOF.swift (kk_range_forEach,
//   kk_range_map, kk_range_filter, kk_range_toList; __kk_long_range_* / __kk_char_range_*
//   equivalents)
//
// NOTE: Range/Progression members that still use the hardcoded range dispatch remain
// separate from these canonical source definitions. Source-backed range HOFs are selected
// by CallTypeChecker+RangeMemberFallback.swift and preserved by the collection lowering
// pass, matching the migration pattern used by MIGRATION-RANGE-003 (RangeCoercion.kt)
// and MIGRATION-COL-002 (ListHOF.kt).
//
// The `first`, `last`, and `step` properties are intentionally NOT included here: they are
// constant-time field reads with no pure-Kotlin expression available (would
// require introducing new native bridge plumbing for zero behavioral change).
// `count()`, `sum()`, and `reversed()` are now included and wired to the shared
// `__kk_range_*` ABI surface.
//
// `count(predicate)` is intentionally NOT included: CallTypeChecker+RangeMemberFallback.swift's
// isValidRangeMemberArity() only accepts a 0-arg `count` for range-like receivers, and (as noted
// above) member resolution for such receivers never falls through to user-declared candidates --
// so a 1-arg overload here would be an uncallable, misleading declaration. Widening that arity
// allow-list is dispatch-wiring work, not a Kotlin-source migration.

// KSP-457: range random APIs are public Kotlin source wrappers around the
// runtime's retained random-engine primitives. The __kk_* names deliberately
// keep these bridges private to the bundled stdlib layer.
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
