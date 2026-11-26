/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/Atomics.kt>.
 */
package kotlin.concurrent

import kotlin.internal.KsSymbolName

@SinceKotlin("1.9")
@KsSymbolName("kk_atomic_long_create")
public external fun AtomicLong(value: Long): AtomicLong
