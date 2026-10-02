/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/Atomics.kt>.
 */
package kotlin.concurrent

import kotlin.internal.KsSymbolName

// The reference atomic value remains owned by the shared runtime atomic box.
// `compareAndExchange` is the CAS core and links directly; `getAndSet`,
// `toString`, and `value` delegate to the retained runtime-backed `load`,
// `store`, and `exchange` members, whose T marshal is correct for every T —
// a function-generic extern return would mis-decode a stored `null` for
// nullable value types such as `Int?` (see atomics/AtomicReference.kt).
@KsSymbolName("__kk_atomic_ref_compareAndExchange")
private external fun <T> AtomicReference<T>.__kkAtomicRefCompareAndExchange(
    expectedValue: T,
    newValue: T
): T

@SinceKotlin("1.9")
public class AtomicReference<T> private constructor() {
    public fun compareAndExchange(expectedValue: T, newValue: T): T =
        __kkAtomicRefCompareAndExchange(expectedValue, newValue)

    public fun getAndSet(newValue: T): T =
        exchange(newValue)

    public override fun toString(): String =
        load().toString()

    public var value: T
        get() = load()
        set(value) {
            store(value)
        }
}
