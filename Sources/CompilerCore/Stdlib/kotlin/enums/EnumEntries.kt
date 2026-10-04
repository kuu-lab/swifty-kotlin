/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/enums/EnumEntries.kt.
 */

package kotlin.enums

import kotlin.internal.KsSymbolName

/**
 * Returns the entries of the reified enum type in declaration order.
 *
 * The compiler expands this declaration at a concrete call site to the
 * enum-specific cached runtime representation. The placeholder body mirrors
 * the existing enumValues intrinsic pattern; the generic body itself is never
 * executed by the compiler-generated stdlib path.
 */
@kotlin.WasExperimental(kotlin.ExperimentalStdlibApi::class)
@SinceKotlin("2.0")
public inline fun <reified T : Enum<T>> enumEntries(): EnumEntries<T> =
    throw NotImplementedError()

/** Compiler intrinsic used by the public reified overload. */
@PublishedApi
@SinceKotlin("1.9")
internal external fun <T : Enum<T>> enumEntriesIntrinsic(): EnumEntries<T>

/** Builds an entries view after evaluating the provider exactly once. */
@PublishedApi
@SinceKotlin("1.8")
internal fun <E : Enum<E>> enumEntries(entriesProvider: () -> Array<E>): EnumEntries<E> =
    enumEntriesFromArray(entriesProvider())

/** Builds an entries view over the supplied array without copying it. */
@PublishedApi
@SinceKotlin("1.8")
internal fun <E : Enum<E>> enumEntries(entries: Array<E>): EnumEntries<E> =
    enumEntriesFromArray(entries)

@KsSymbolName("__kk_enum_entries_from_array")
private external fun <E : Enum<E>> enumEntriesFromArray(entries: Array<E>): EnumEntries<E>
