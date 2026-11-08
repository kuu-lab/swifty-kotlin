@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package kotlin.ranges

import kotlin.random.Random
import kotlin.random.nextInt
import kotlin.random.nextLong
import kotlin.random.nextUInt
import kotlin.random.nextULong

// MIGRATION-RANGE-002: Range random and randomOrNull higher-order functions.
// Migrated to pure Kotlin calling Random.nextInt/nextLong/nextUInt/nextULong.

public fun IntRange.random(): Int = random(Random)
public fun IntRange.random(random: Random): Int {
    try {
        return random.nextInt(this)
    } catch (e: IllegalArgumentException) {
        throw NoSuchElementException(e.message)
    }
}
public fun IntRange.randomOrNull(): Int? = randomOrNull(Random)
public fun IntRange.randomOrNull(random: Random): Int? =
    if (isEmpty()) null else random(random)

public fun LongRange.random(): Long = random(Random)
public fun LongRange.random(random: Random): Long {
    try {
        return random.nextLong(this)
    } catch (e: IllegalArgumentException) {
        throw NoSuchElementException(e.message)
    }
}
public fun LongRange.randomOrNull(): Long? = randomOrNull(Random)
public fun LongRange.randomOrNull(random: Random): Long? =
    if (isEmpty()) null else random(random)

public fun CharRange.random(): Char = random(Random)
public fun CharRange.random(random: Random): Char {
    try {
        return Char(random.nextInt(first.toInt(), last.toInt() + 1))
    } catch (e: IllegalArgumentException) {
        throw NoSuchElementException(e.message)
    }
}
public fun CharRange.randomOrNull(): Char? = randomOrNull(Random)
public fun CharRange.randomOrNull(random: Random): Char? =
    if (isEmpty()) null else random(random)

public fun UIntRange.random(): UInt = random(Random)
public fun UIntRange.random(random: Random): UInt {
    try {
        return random.nextUInt(this)
    } catch (e: IllegalArgumentException) {
        throw NoSuchElementException(e.message)
    }
}
public fun UIntRange.randomOrNull(): UInt? = randomOrNull(Random)
public fun UIntRange.randomOrNull(random: Random): UInt? =
    if (isEmpty()) null else random(random)

public fun ULongRange.random(): ULong = random(Random)
public fun ULongRange.random(random: Random): ULong {
    try {
        return random.nextULong(this)
    } catch (e: IllegalArgumentException) {
        throw NoSuchElementException(e.message)
    }
}
public fun ULongRange.randomOrNull(): ULong? = randomOrNull(Random)
public fun ULongRange.randomOrNull(random: Random): ULong? =
    if (isEmpty()) null else random(random)
