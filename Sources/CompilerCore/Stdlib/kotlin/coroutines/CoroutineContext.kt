/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/CoroutineContext.kt.
 */

package kotlin.coroutines

import kotlin.internal.KsSymbolName

// KSP-1131/KSP-1143: the context's abstract operations and `plus` are declared
// in bundled Kotlin source. The runtime models a context as a fixed-key
// element collection rather than upstream's `CombinedContext` chain, so the
// declarations bridge native handles to the residual runtime ABI while
// dispatching source objects to their Kotlin overrides. KSP-1144 places the Element defaults in
// the same source owner as the upstream stdlib.
public interface CoroutineContext {
    @KsSymbolName("__kk_context_get_dispatch")
    public operator fun <E : Element> get(key: Key<E>): E?

    @KsSymbolName("kk_context_fold")
    public fun <R> fold(initial: R, operation: (R, Element) -> R): R

    @KsSymbolName("__kk_context_plus_dispatch")
    public operator fun plus(context: CoroutineContext): CoroutineContext

    @KsSymbolName("__kk_context_minusKey_dispatch")
    public fun minusKey(key: Key<*>): CoroutineContext

    /** A context element is a context containing only itself. */
    public interface Element : CoroutineContext {
        public val key: CoroutineContext.Key<*>

        @Suppress("UNCHECKED_CAST")
        public override operator fun <E : Element> get(key: CoroutineContext.Key<E>): E? =
            if (this.key == key) this as E else null

        public override fun <R> fold(initial: R, operation: (R, Element) -> R): R =
            operation(initial, this)

        public override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext {
            if (this.key == key) return EmptyCoroutineContext
            return this
        }
    }
}
