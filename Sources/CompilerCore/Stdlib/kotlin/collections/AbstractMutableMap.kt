/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/common/src/kotlin/collections/AbstractMutableMap.kt.
 */

package kotlin.collections

// KSP-930: the nominal AbstractMutableMap<K, V> declaration is source-backed
// here; the compiler-side shell remains the fallback for non-bundled contexts.

/**
 * Provides a skeletal implementation of the MutableMap interface.
 */
public abstract class AbstractMutableMap<K, V> protected constructor() : AbstractMap<K, V>(), MutableMap<K, V> {
    abstract override fun put(key: K, value: V): V?

    abstract override val entries: MutableSet<MutableMap.MutableEntry<K, V>>
}
