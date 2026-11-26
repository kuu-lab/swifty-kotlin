/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/enums/EnumEntries.kt.
 */

package kotlin.enums

import kotlin.internal.KsSymbolName

@kotlin.WasExperimental(kotlin.ExperimentalStdlibApi::class)
@SinceKotlin("2.0")
public inline fun <reified T : Enum<T>> enumEntries(): EnumEntries<T> =
    throw NotImplementedError()

@PublishedApi
@SinceKotlin("1.9")
internal external fun <T : Enum<T>> enumEntriesIntrinsic(): EnumEntries<T>

@PublishedApi
@SinceKotlin("1.8")
internal fun <E : Enum<E>> enumEntries(entriesProvider: () -> Array<E>): EnumEntries<E> =
    enumEntriesFromArray(entriesProvider())

@PublishedApi
@SinceKotlin("1.8")
internal fun <E : Enum<E>> enumEntries(entries: Array<E>): EnumEntries<E> =
    enumEntriesFromArray(entries)

@KsSymbolName("__kk_enum_entries_from_array")
private external fun <E : Enum<E>> enumEntriesFromArray(entries: Array<E>): EnumEntries<E>
