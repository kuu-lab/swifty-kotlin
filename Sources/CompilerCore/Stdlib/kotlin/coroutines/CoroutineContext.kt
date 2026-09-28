/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/coroutines/CoroutineContext.kt.
 */

package kotlin.coroutines

// KSP-1131: the context's abstract operations remain on the residual runtime
// registration path until their separate migration. KSP-1144 places the
// Element defaults in the same source owner as the upstream stdlib.
public interface CoroutineContext {
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
