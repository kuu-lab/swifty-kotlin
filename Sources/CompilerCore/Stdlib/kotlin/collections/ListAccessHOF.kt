package kotlin.collections

import kotlin.random.Random

// KSP-939: List(size, init) initializer factory. The List<out E> nominal
// declaration itself already lives in List.kt (KSP-697); indexed access and
// collection members remain compiler/runtime residuals until their dedicated
// migration tasks land.

/**
 * Creates a read-only list whose elements are produced in ascending index order.
 */
@SinceKotlin("1.1")
@kotlin.internal.InlineOnly
public inline fun <T> List(size: Int, init: (index: Int) -> T): List<T> =
    MutableList(size, init)

// MIGRATION-COL-007
// List access helpers migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeCollections.swift (kk_list_getOrNull,
// kk_list_elementAt*, kk_list_elementAt) and RuntimeCollectionHOF.swift
// (kk_list_getOrElse, kk_list_elementAtOrElse).

public fun <T> List<T>.getOrNull(index: Int): T? {
    if (index >= 0 && index < size) {
        return this[index]
    }
    return null
}

public fun <T> List<T>.getOrElse(index: Int, defaultValue: (Int) -> T): T {
    if (index >= 0 && index < size) {
        return this[index]
    }
    return defaultValue(index)
}

public fun <T> List<T>.elementAt(index: Int): T {
    if (index < 0 || index >= size) {
        throw IndexOutOfBoundsException("Index $index out of bounds for length $size")
    }
    return this[index]
}

public fun <T> List<T>.elementAtOrNull(index: Int): T? {
    if (index >= 0 && index < size) {
        return this[index]
    }
    return null
}

public fun <T> List<T>.elementAtOrElse(index: Int, defaultValue: (Int) -> T): T {
    if (index >= 0 && index < size) {
        return this[index]
    }
    return defaultValue(index)
}

// KSP-1509
// List-specific random()/randomOrNull() overrides. Collection<T>'s versions in
// Collections.kt were unreachable for List receivers because a member function
// always wins over an extension with the same name, and List used to declare
// these as synthetic members (HeaderHelpers+SyntheticListAggregateMembers.swift,
// deleted by this migration). This override uses direct indexed access instead
// of the linear scan Collection<T> needs. kk_list_random/kk_list_randomOrNull
// stay in place as the Collection-interface fallback for --no-stdlib/precompiled
// -metadata builds that have no bundled Kotlin source to resolve against (see
// HeaderHelpers+SyntheticCollectionTypeFallbacks.swift).

/**
 * Returns a random element from this list.
 */
@SinceKotlin("1.3")
@kotlin.internal.InlineOnly
public inline fun <T> List<T>.random(): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    return this[Random.nextInt(size)]
}

/**
 * Returns a random element from this list using the specified random source.
 */
@SinceKotlin("1.3")
public fun <T> List<T>.random(random: Random): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    return this[random.nextInt(size)]
}

/**
 * Returns a random element from this list, or `null` if it is empty.
 */
@SinceKotlin("1.4")
@kotlin.internal.InlineOnly
public inline fun <T> List<T>.randomOrNull(): T? {
    if (isEmpty()) return null
    return this[Random.nextInt(size)]
}

/**
 * Returns a random element from this list using the specified random source,
 * or `null` if it is empty.
 */
@SinceKotlin("1.4")
public fun <T> List<T>.randomOrNull(random: Random): T? {
    if (isEmpty()) return null
    return this[random.nextInt(size)]
}
