/*
 * Copyright 2010-2025 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/atomics/Atomics.common.kt>.
 */
@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package kotlin.concurrent.atomics

import kotlin.internal.KsSymbolName

@kotlin.concurrent.atomics.ExperimentalAtomicApi
@SinceKotlin("2.1")
@KsSymbolName("kk_atomic_bool_create")
public external fun AtomicBoolean(value: Boolean): AtomicBoolean
