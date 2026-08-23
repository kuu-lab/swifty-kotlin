/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/MutableListIterator.kt.
 */

package kotlin.collections

// KSP-945: keep the public MutableListIterator nominal declaration in bundled
// Kotlin source. The compiler residuals for iterator mutation and the shared
// list-iterator runtime remain separate surfaces.

/**
 * An iterator over a mutable list that supports element insertion, replacement,
 * and removal while iterating.
 */
public interface MutableListIterator<T> : ListIterator<T>, MutableIterator<T>
