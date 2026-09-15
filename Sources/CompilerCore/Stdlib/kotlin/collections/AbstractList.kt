/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/AbstractList.kt.
 */

package kotlin.collections

// KSP-697/KSP-700: source-backed nominal shell. `get` overrides the
// source-backed `List.get` external bridge declaration (see List.kt).
public abstract class AbstractList<out E> protected constructor() : AbstractCollection<E>(), List<E> {
    public abstract override operator fun get(index: Int): E
}
