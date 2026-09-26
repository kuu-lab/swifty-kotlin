/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
package kotlin.concurrent.atomics

/**
 * Creates an atomic Int value through the canonical atomics-package API.
 *
 * The nominal type remains the existing `kotlin.concurrent.atomics.AtomicInt` typealias
 * until the receiver members are migrated by KSP-1113. The underlying constructor retains the
 * runtime-backed allocation owned by the concurrent atomic implementation.
 */
@kotlin.concurrent.atomics.ExperimentalAtomicApi
@SinceKotlin("2.1")
public fun AtomicInt(value: Int): AtomicInt =
    kotlin.concurrent.AtomicInt(value)
