/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/MutableIterator.kt.
 */

package kotlin.collections

// KSP-943: the nominal MutableIterator declaration is source-backed here. The
// compiler-side shell remains the fallback for contexts without bundled stdlib
// source, such as --no-stdlib and precompiled metadata.

/**
 * An iterator over a mutable collection that can remove the last returned element.
 */
public interface MutableIterator<out T> : Iterator<T> {
    public fun remove(): Unit
}
