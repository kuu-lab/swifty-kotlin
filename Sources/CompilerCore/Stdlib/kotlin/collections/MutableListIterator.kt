/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/MutableListIterator.kt.
 */

package kotlin.collections

public interface MutableListIterator<T> : ListIterator<T>, MutableIterator<T> {
    public fun set(element: T): Unit

    public fun add(element: T): Unit
}
