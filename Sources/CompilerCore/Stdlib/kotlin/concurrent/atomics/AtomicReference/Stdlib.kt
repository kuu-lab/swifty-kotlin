/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

/**
 * Creates an atomic reference to the given [value] through the canonical
 * atomics-package API.
 *
 * `AtomicReference` is now a real class in this package, so the factory binds
 * directly to the runtime-backed allocation (`kk_atomic_ref_create`) instead of
 * delegating through `kotlin.concurrent.AtomicReference`.
 */
@kotlin.concurrent.atomics.ExperimentalAtomicApi
@SinceKotlin("2.1")
@KsSymbolName("kk_atomic_ref_create")
public external fun <T> AtomicReference(value: T): AtomicReference<T>
