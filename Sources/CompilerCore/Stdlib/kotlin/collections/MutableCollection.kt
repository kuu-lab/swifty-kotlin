/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/Collections.kt.
 */

package kotlin.collections

import kotlin.internal.KsSymbolName

public interface MutableCollection<E> : Collection<E>, MutableIterable<E> {
    @KsSymbolName("__kk_mutable_collection_add_throwing")
    @IgnorableReturnValue
    public external fun add(element: E): Boolean

    @KsSymbolName("__kk_mutable_collection_addAll_throwing")
    @IgnorableReturnValue
    public external fun addAll(elements: Collection<out E>): Boolean

    @KsSymbolName("__kk_mutable_collection_clear_throwing")
    public external fun clear(): Unit

    @KsSymbolName("__kk_mutable_collection_remove_throwing")
    @IgnorableReturnValue
    public external fun remove(element: E): Boolean

    @KsSymbolName("__kk_mutable_collection_removeAll_throwing")
    @IgnorableReturnValue
    public external fun removeAll(elements: Collection<out E>): Boolean

    @KsSymbolName("__kk_mutable_collection_retainAll_throwing")
    @IgnorableReturnValue
    public external fun retainAll(elements: Collection<out E>): Boolean
}
