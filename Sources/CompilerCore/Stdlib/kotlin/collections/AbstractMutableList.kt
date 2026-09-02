/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib common/src/kotlin/collections/AbstractMutableList.kt.
 */

package kotlin.collections

// KSP-929: the nominal `AbstractMutableList<E>` declaration is source-backed
// here; the compiler-side shell remains the fallback for non-bundled contexts.

/**
 * Provides a skeletal implementation of the [MutableList] interface.
 */
public abstract class AbstractMutableList<E> protected constructor() : AbstractMutableCollection<E>(), MutableList<E> {
    // These storage primitives are redeclared by the platform implementation
    // because concrete mutable list implementations must provide them.
    abstract override fun set(index: Int, element: E): E

    abstract override fun removeAt(index: Int): E

    abstract override fun add(index: Int, element: E)
}
