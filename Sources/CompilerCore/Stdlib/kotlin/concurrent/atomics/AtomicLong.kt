/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
package kotlin.concurrent.atomics

// KSP-1104: canonical atomics AtomicLong arithmetic/assignment and CAS-update
// operators. The receiver aliases the runtime-backed kotlin.concurrent.AtomicLong
// shell, so the bodies delegate to its retained addAndFetch/load/compareAndSet
// core operations; no new runtime bridge is required.

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.incrementAndFetch(): Long = addAndFetch(1L)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicLong.decrementAndFetch(): Long = addAndFetch(-1L)

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public operator fun AtomicLong.plusAssign(delta: Long) {
    addAndFetch(delta)
}

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public operator fun AtomicLong.minusAssign(delta: Long) {
    addAndFetch(-delta)
}

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public inline fun AtomicLong.update(transform: (Long) -> Long): Unit {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return
    }
}

@ExperimentalAtomicApi
@SinceKotlin("2.1")
public inline fun AtomicLong.updateAndFetch(transform: (Long) -> Long): Long {
    while (true) {
        val old = load()
        val newValue = transform(old)
        if (compareAndSet(old, newValue)) return newValue
    }
}
