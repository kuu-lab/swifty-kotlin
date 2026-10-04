/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/properties/PropertyReferenceDelegates.kt
 * and libraries/stdlib/src/kotlin/util/Lateinit.kt.
 */

package kotlin

import kotlin.reflect.KProperty
import kotlin.reflect.KProperty0

@SinceKotlin("1.4")
public inline operator fun <V> KProperty0<V>.getValue(thisRef: Any?, property: KProperty<*>): V =
    get()

@SinceKotlin("1.2")
public inline val KProperty0<*>.isInitialized: Boolean
    get() = throw NotImplementedError("Implementation is intrinsic")
