/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/RandomAccess.kt
 * (JVM maps this to the java.util.RandomAccess marker interface).
 */

package kotlin.collections

// KSP-669: nominal `kotlin.collections.RandomAccess` marker interface migrated
// out of the synthetic self-registration; on bundle load it reuses the synthetic
// shell, which otherwise remains as a fallback for non-bundled contexts.

/**
 * Marker interface indicating that the [List] implementation supports fast
 * (generally constant time) indexed access to its elements.
 */
public interface RandomAccess
