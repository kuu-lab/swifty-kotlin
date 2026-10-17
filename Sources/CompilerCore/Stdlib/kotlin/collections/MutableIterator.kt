/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/MutableIterator.kt.
 */

package kotlin.collections

// KSP-943: The compiler-side MutableIterator shell remains the fallback for
// contexts without bundled stdlib source, such as --no-stdlib and precompiled
// metadata.

public interface MutableIterator<out T> : Iterator<T> {
    public fun remove(): Unit
}
