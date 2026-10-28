package kotlin.collections

import kotlin.random.Random

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

// JVM resolves `elementAt` through `Iterable.elementAt`, whose List branch
// delegates to `get` so bounds errors keep the implementation's own exception
// type and message.
public fun <T> List<T>.elementAt(index: Int): T = this[index]

public fun <T> List<T>.elementAtOrNull(index: Int): T? {
    if (index >= 0 && index < size) {
        return this[index]
    }
    return null
}

public inline fun <T> List<T>.elementAtOrElse(index: Int, defaultValue: (Int) -> T): T {
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

@SinceKotlin("1.3")
@kotlin.internal.InlineOnly
public inline fun <T> List<T>.random(): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    return this[Random.nextInt(size)]
}

@SinceKotlin("1.3")
public fun <T> List<T>.random(random: Random): T {
    if (isEmpty()) throw NoSuchElementException("Collection is empty.")
    return this[random.nextInt(size)]
}

@SinceKotlin("1.4")
@kotlin.internal.InlineOnly
public inline fun <T> List<T>.randomOrNull(): T? {
    if (isEmpty()) return null
    return this[Random.nextInt(size)]
}

@SinceKotlin("1.4")
public fun <T> List<T>.randomOrNull(random: Random): T? {
    if (isEmpty()) return null
    return this[random.nextInt(size)]
}
