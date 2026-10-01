/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 * Derived from kotlin-native/runtime/src/main/kotlin/kotlin/collections/ArrayUtil.kt.
 */
package kotlin.collections

// Reading a slot before it has been initialized is implementation-dependent.
// The array allocation primitive uses null slots until callers assign values.
@PublishedApi
@Suppress("NOTHING_TO_INLINE", "UNCHECKED_CAST")
internal inline fun <E> arrayOfUninitializedElements(size: Int): Array<E> {
    require(size >= 0) { "capacity must be non-negative." }
    return arrayOfNulls<Any?>(size) as Array<E>
}
