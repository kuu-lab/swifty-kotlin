/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Iterables.kt
 * (builtins declaration of kotlin.collections.MutableIterable).
 */

package kotlin.collections

// KSP-633: the nominal `MutableIterable<out T>` declaration is source-backed
// here; on bundle load it reuses the synthetic shell registered by
// `HeaderHelpers+SyntheticIterableRegistry.swift`, which remains as the
// fallback for contexts without the bundled stdlib.
// `iterator()` is intentionally omitted (as with `Comparable.compareTo` in
// KSP-669) and stays a compiler residual: the covariant override of the
// read-only `Iterable.iterator()` has to be re-typed against the reused shell's
// type parameter, which library metadata cannot express yet (BUG-183).

/**
 * Classes that inherit from this interface can be represented as a sequence of
 * elements that can be iterated over and whose iterator supports removal.
 */
public interface MutableIterable<out T> : Iterable<T>
