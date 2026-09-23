/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

// The canonical atomics type is currently an alias of the runtime-backed
// kotlin.concurrent.AtomicReference shell. Most receiver APIs keep their
// runtime-linked member stubs as the source of truth: `value`, `load`,
// `store`, `exchange`, `getAndSet` and `toString` already resolve to members
// backed by `__kk_atomic_ref_*` links whose T marshal is correct for every T.
// A source-backed extension would only shadow them with a function-generic
// extern call whose T return mis-decodes a stored `null` for nullable value
// types such as `Int?` (reading back the type default), and `var value: T`
// cannot even be declared on a receiver here — a bundled extension property
// cannot name the class type parameter, and a star-projected
// `AtomicReference<*>` variant would shadow the member's T-typed getter for
// atomics callers.
//
// `compareAndExchange` is the one decl whose member is already superseded by
// the `kotlin.concurrent` migration extension, so the canonical decl lives
// here and wins on the atomics package preference. Its private extern
// delegates to the same runtime link the member used.
@KsSymbolName("__kk_atomic_ref_compareAndExchange")
private external fun <T> AtomicReference<T>.__kkAtomicRefCompareAndExchange(
    expectedValue: T,
    newValue: T
): T

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicReference<T>.compareAndExchange(expectedValue: T, newValue: T): T =
    __kkAtomicRefCompareAndExchange(expectedValue, newValue)
