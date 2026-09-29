/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Collections.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-697/705: the mutable collection shell and its Collection addAll member
// are source-backed. The member keeps the demoted runtime bridge as its ABI.
public interface MutableCollection<E> : Collection<E>, MutableIterable<E> {
    /**
     * Adds all elements of [elements] to this mutable collection.
     */
    @KsSymbolName("__kk_mutable_collection_addAll")
    @IgnorableReturnValue
    public external fun addAll(elements: Collection<out E>): Boolean
}
