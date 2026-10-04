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
 * Creates an atomic Long value through the canonical atomics-package API.
 *
 * `AtomicLong` is now a real class in this package, so the factory binds
 * directly to the runtime-backed allocation (`kk_atomic_long_create`) instead
 * of delegating through `kotlin.concurrent.AtomicLong`.
 */
@kotlin.concurrent.atomics.ExperimentalAtomicApi
@SinceKotlin("2.1")
@KsSymbolName("kk_atomic_long_create")
public external fun AtomicLong(value: Long): AtomicLong
