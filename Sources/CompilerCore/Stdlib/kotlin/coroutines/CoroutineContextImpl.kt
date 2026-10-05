/*
 * Copyright 2010-2020 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/CoroutineContextImpl.kt.
 */

@file:Suppress("KSWIFTK-SEMA-ABSTRACT")

package kotlin.coroutines

import kotlin.coroutines.CoroutineContext.Element
import kotlin.coroutines.CoroutineContext.Key

/**
 * Base class for [CoroutineContext.Element] implementations.
 *
 * The key is retained by the source-backed property (KSP-1137).
 */
@SinceKotlin("1.3")
public abstract class AbstractCoroutineContextElement(public override val key: Key<*>) : Element

@SinceKotlin("1.3")
@ExperimentalStdlibApi
public abstract class AbstractCoroutineContextKey<B : Element, E : B>(
    baseKey: Key<B>,
    private val safeCast: (element: Element) -> E?
) : Key<E> {
    private val topmostKey: Key<*> = findTopmostKey(baseKey)

    private fun findTopmostKey(key: Key<*>): Key<*> =
        if (key is AbstractCoroutineContextKey<*, *>) key.topmostKey else key

    internal fun tryCast(element: Element): E? = safeCast(element)

    internal fun isSubKey(key: Key<*>): Boolean =
        key === this || topmostKey === key
}

@SinceKotlin("1.3")
@ExperimentalStdlibApi
@Suppress("UNCHECKED_CAST")
public fun <E : Element> Element.getPolymorphicElement(key: Key<E>): E? {
    if (key is AbstractCoroutineContextKey<*, *>) {
        return if (key.isSubKey(this.key)) key.tryCast(this) as? E else null
    }
    return if (this.key === key) this as E else null
}

@SinceKotlin("1.3")
@ExperimentalStdlibApi
public fun Element.minusPolymorphicKey(key: Key<*>): CoroutineContext {
    if (key is AbstractCoroutineContextKey<*, *>) {
        return if (key.isSubKey(this.key) && key.tryCast(this) != null) EmptyCoroutineContext else this
    }
    return if (this.key === key) EmptyCoroutineContext else this
}

// KSP-1145: EmptyCoroutineContext's public behavior is pure Kotlin stdlib
// semantics. The compiler/runtime context bridges remain responsible for
// context values that contain runtime-owned elements.
public object EmptyCoroutineContext : CoroutineContext {
    public override fun <E : Element> get(key: Key<E>): E? = null

    public override fun <R> fold(
        initial: R,
        operation: (R, Element) -> R
    ): R = initial

    public override operator fun plus(context: CoroutineContext): CoroutineContext = context

    public override fun minusKey(key: Key<*>): CoroutineContext = this

    public override fun hashCode(): Int = 0

    public override fun toString(): String = "EmptyCoroutineContext"
}
