/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Iterables.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-1061: the interface and its iterator member are source-backed. The
// bridge supports built-in collection boxes and source-defined implementations.
public interface Iterable<out E> {
    @KsSymbolName("kk_iterable_iterator")
    public operator fun iterator(): Iterator<E>
}
