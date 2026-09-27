/*
 * Copyright 2010-2026 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/concurrent/Atomics.kt>.
 */
package kotlin.concurrent

import kotlin.internal.KsSymbolName

/**
 * A reference to a value of type [T] that can be read and updated atomically.
 *
 * The instance itself is the shared runtime atomic box: allocation stays with
 * the `kk_atomic_ref_create` ABI entry point, while the `value` property and
 * the compare/exchange receiver surface remain residual synthetic
 * registrations (KSP-1098) backed by the `__kk_atomic_ref_*` links.
 */
@SinceKotlin("1.9")
public class AtomicReference<T> {
    /**
     * Creates a new [AtomicReference] holding the given initial [value].
     */
    @KsSymbolName("kk_atomic_ref_create")
    public constructor(value: T)
}
