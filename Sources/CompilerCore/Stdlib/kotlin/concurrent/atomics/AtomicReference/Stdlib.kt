/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
package kotlin.concurrent.atomics

/**
 * Creates an atomic reference to the given [value] through the canonical
 * atomics-package API.
 *
 * The nominal type remains the existing `kotlin.concurrent.atomics.AtomicReference`
 * typealias of `kotlin.concurrent.AtomicReference`; the call delegates to the
 * runtime-backed constructor (`kk_atomic_ref_create`) owned by the concurrent
 * atomic implementation.
 */
@kotlin.concurrent.atomics.ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun <T> AtomicReference(value: T): kotlin.concurrent.AtomicReference<T> =
    kotlin.concurrent.AtomicReference(value)
