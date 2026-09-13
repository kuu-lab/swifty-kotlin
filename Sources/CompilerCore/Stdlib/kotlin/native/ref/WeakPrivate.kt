/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/ref/WeakPrivate.kt>.
 */

package kotlin.native.ref

@PublishedApi
internal abstract class WeakReferenceImpl {
    abstract fun get(): Any?
}
